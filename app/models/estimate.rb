# A patient-facing quote, built from a course of treatment's planned items. Accepting it can
# convert it into an invoice. (Phase 6: the AI scribe drafts these for review.)
class Estimate < ApplicationRecord
  STATUSES = %w[draft sent accepted rejected expired].freeze

  belongs_to :patient
  belongs_to :billing_account, optional: true
  belongs_to :course_of_treatment, optional: true
  has_many :estimate_lines, dependent: :destroy
  # C1 — Drag-drop attachments (X-ray screenshots, intra-oral photos,
  # clinical reference images that the dentist wants to ship alongside
  # the quote so the patient understands what they're paying for).
  has_many_attached :attachments

  validates :status, inclusion: { in: STATUSES }
  before_validation :assign_number, on: :create

  # Build an estimate from a COT's non-voided items (planned + completed).
  def self.from_course(cot)
    est = new(patient_id: cot.patient_id, billing_account_id: cot.billing_account_id,
              course_of_treatment_id: cot.id, valid_until: 30.days.from_now.to_date,
              provider_name: cot.provider_name)
    cot.treatment_items.where.not(status: "voided").includes(:procedure_code).each do |item|
      pc = item.procedure_code
      est.estimate_lines.build(
        procedure_code_id: pc&.id, treatment_item_id: item.id,
        code: pc&.code, description: pc&.description, tooth_number: item.tooth_number,
        quantity: 1, unit_fee_cents: item.fee_cents.to_i, vat_treatment: item.vat_treatment,
        visit: item.visit, icd10_code: item.icd10_code
      )
    end
    est.recalculate
    est
  end

  def recalculate
    estimate_lines.each(&:compute_totals)
    self.total_cents = estimate_lines.sum { |l| l.line_total_cents.to_i }
    self.vat_cents   = estimate_lines.sum { |l| l.vat_cents.to_i }
    self.subtotal_cents = total_cents - vat_cents
    self
  end

  def mark_sent!  = update!(status: "sent", sent_at: Time.current)

  # Accept and convert to an invoice for the same course of treatment.
  # Idempotent + race-safe: a pessimistic row lock serialises concurrent accepts, and the
  # status guard inside the lock stops a double-submit from creating a SECOND invoice.
  def accept_and_invoice!(invoice_date: Date.current)
    transaction do
      lock! # FOR UPDATE — second concurrent accept waits, then sees status=accepted and bails
      if status == "accepted"
        errors.add(:base, "Estimate already accepted")
        raise ActiveRecord::RecordInvalid, self
      end
      update!(status: "accepted", accepted_at: Time.current)
      inv = Invoice.new(patient_id: patient_id, billing_account_id: billing_account_id,
                        course_of_treatment_id: course_of_treatment_id, invoice_date: invoice_date,
                        provider_name: provider_name)  # carry the treating dentist through to the invoice
      estimate_lines.each do |l|
        inv.invoice_lines.build(procedure_code_id: l.procedure_code_id, treatment_item_id: l.treatment_item_id,
          code: l.code, description: l.description, tooth_number: l.tooth_number,
          quantity: l.quantity, unit_fee_cents: l.unit_fee_cents, vat_treatment: l.vat_treatment)
      end
      inv.recalculate
      inv.save!
      inv
    end
  end

  def total = total_cents.to_i / 100.0
  def medical_total = estimate_lines.sum(&:medical_cents) / 100.0
  def self_total    = estimate_lines.sum(&:self_cents) / 100.0
  def lines_by_visit = estimate_lines.group_by { |l| l.visit.to_i }.sort.to_h

  private

  def assign_number
    self.estimate_number ||= DocumentSequence.next_number("estimate", prefix: "EST")
  end
end
