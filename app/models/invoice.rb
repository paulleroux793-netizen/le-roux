# A patient-pay invoice (we don't claim from medical aid — this is the document the patient
# submits to their own scheme). Sequential gap-free number. Immutable once created: corrections
# are a void + new invoice, never an in-place edit.
class Invoice < ApplicationRecord
  STATUSES = %w[open part_paid paid written_off void].freeze

  belongs_to :patient
  belongs_to :billing_account, optional: true
  belongs_to :course_of_treatment, optional: true
  has_many :invoice_lines, dependent: :destroy
  has_many :payments, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }

  before_validation :assign_number, on: :create
  before_validation :set_invoice_date, on: :create

  scope :outstanding, -> { where(status: %w[open part_paid]) }

  # Build an invoice from a course of treatment's COMPLETED items (charting -> billing).
  # Bills ONLY items not already on a non-void invoice line — prevents double-billing on a
  # second "generate invoice" while still allowing staged/progress billing of newly-completed
  # items later (a voided invoice releases its items, so they can be re-billed).
  def self.from_course(cot, invoice_date: Date.current)
    invoice = new(patient_id: cot.patient_id, billing_account_id: cot.billing_account_id,
                  course_of_treatment_id: cot.id, invoice_date: invoice_date,
                  provider_name: cot.provider_name)
    already_billed = InvoiceLine.joins(:invoice).where.not(treatment_item_id: nil)
                                .where(invoices: { void: false }).pluck(:treatment_item_id).to_set
    cot.treatment_items.completed.includes(:procedure_code).each do |item|
      next if already_billed.include?(item.id)

      pc = item.procedure_code
      invoice.invoice_lines.build(
        procedure_code_id: pc&.id, treatment_item_id: item.id,
        code: pc&.code, description: pc&.description, tooth_number: item.tooth_number,
        quantity: 1, unit_fee_cents: item.fee_cents.to_i, vat_treatment: item.vat_treatment,
        icd10_code: item.icd10_code
      )
    end
    invoice.recalculate
    invoice
  end

  # Recompute header totals from lines (call before save when lines change).
  def recalculate
    invoice_lines.each(&:compute_totals)
    self.total_cents = invoice_lines.sum { |l| l.line_total_cents.to_i }
    self.vat_cents   = invoice_lines.sum { |l| l.vat_cents.to_i }
    self.subtotal_cents = total_cents - vat_cents
    self
  end

  # Apply money to this invoice. Returns the amount actually APPLIED (cents). Any excess
  # over the outstanding balance does NOT inflate paid_cents — it is returned to the
  # account as credit (if the invoice has a billing account), so over-payments are tracked
  # as real, re-usable credit instead of vanishing into a negative balance.
  def register_payment!(amount_cents)
    amt = amount_cents.to_i
    return 0 if amt <= 0
    # Void/written-off invoices are settled/cancelled — never let a payment resurrect them.
    return 0 if void? || written_off?

    applied = [ amt, outstanding_cents ].min
    applied = amt if billing_account.nil? # no account to hold credit → keep legacy behaviour (no money lost)
    excess  = amt - applied

    self.paid_cents += applied
    recompute_status
    save!

    billing_account&.add_credit!(excess) if excess.positive?
    applied
  end

  # Account credit applied onto this invoice (caller has already capped it at the balance).
  def apply_credit!(amount_cents)
    self.paid_cents += [ amount_cents.to_i, outstanding_cents ].min
    recompute_status
    save!
  end

  # Reverse part/all of a payment already applied (used by Payment#reverse!). Reopens status.
  def reduce_paid!(amount_cents)
    self.paid_cents = [ paid_cents - amount_cents.to_i, 0 ].max
    recompute_status
    save!
  end

  # Bad debt: clear the invoice off the books without pretending it was paid or voided.
  # Drops out of `outstanding` (and thus age analysis). Admin action; audit at the caller.
  def write_off!(reason: nil)
    return false if void? || written_off?

    update!(status: "written_off", notes: [ notes, "WRITTEN OFF: #{reason}" ].compact.join(" | "))
  end

  # Immutability: a finalised invoice is voided, never edited. Correction = new invoice.
  def void!(reason: nil)
    update!(void: true, status: "void", notes: [ notes, "VOID: #{reason}" ].compact.join(" | "))
  end

  def written_off? = status == "written_off"
  def settled?     = void? || written_off? || paid_cents.to_i >= total_cents.to_i
  def outstanding_cents = [ total_cents.to_i - paid_cents.to_i, 0 ].max

  def total = total_cents.to_i / 100.0
  def balance = (total_cents.to_i - paid_cents.to_i) / 100.0
  def medical_total = invoice_lines.sum(&:medical_cents) / 100.0
  def self_total    = invoice_lines.sum(&:self_cents) / 100.0

  private

  # open / part_paid / paid from paid_cents — never touches void or written_off.
  def recompute_status
    return if void? || written_off?

    self.status = if paid_cents >= total_cents then "paid"
                  elsif paid_cents.positive?   then "part_paid"
                  else "open"
                  end
  end

  def assign_number
    self.invoice_number ||= DocumentSequence.next_number("invoice", prefix: "INV")
  end

  def set_invoice_date
    self.invoice_date ||= Date.current
  end
end
