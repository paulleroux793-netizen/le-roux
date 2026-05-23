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
  def self.from_course(cot, invoice_date: Date.current)
    invoice = new(patient_id: cot.patient_id, billing_account_id: cot.billing_account_id,
                  course_of_treatment_id: cot.id, invoice_date: invoice_date)
    cot.treatment_items.completed.includes(:procedure_code).each do |item|
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

  def register_payment!(amount_cents)
    self.paid_cents += amount_cents
    self.status = if paid_cents >= total_cents then "paid" elsif paid_cents.positive? then "part_paid" else "open" end
    save!
  end

  # Immutability: a finalised invoice is voided, never edited. Correction = new invoice.
  def void!(reason: nil)
    update!(void: true, status: "void", notes: [ notes, "VOID: #{reason}" ].compact.join(" | "))
  end

  def total = total_cents.to_i / 100.0
  def balance = (total_cents.to_i - paid_cents.to_i) / 100.0
  def medical_total = invoice_lines.sum(&:medical_cents) / 100.0
  def self_total    = invoice_lines.sum(&:self_cents) / 100.0

  private

  def assign_number
    self.invoice_number ||= DocumentSequence.next_number("invoice", prefix: "INV")
  end

  def set_invoice_date
    self.invoice_date ||= Date.current
  end
end
