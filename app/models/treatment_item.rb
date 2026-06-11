# One planned/performed procedure within a Course of Treatment. Ticking it "completed"
# is what later moves it onto an invoice (Phase 3) — the charting→billing link.
class TreatmentItem < ApplicationRecord
  STATUSES = %w[planned completed failed voided].freeze

  belongs_to :course_of_treatment
  belongs_to :procedure_code

  validates :status, inclusion: { in: STATUSES }

  before_validation :snapshot_fee_and_vat, on: :create

  scope :completed, -> { where(status: "completed") }
  scope :billable,  -> { where(status: "completed") }

  # Lab cases: an item is "out at the lab" once it has been sent and not yet returned.
  scope :at_lab, -> { where.not(lab_sent_on: nil).where(lab_returned_on: nil) }
  scope :returned_recently, ->(days = 30) {
    where.not(lab_returned_on: nil).where(lab_returned_on: (Date.current - days)..Date.current)
  }

  def at_lab?
    lab_sent_on.present? && lab_returned_on.nil?
  end

  # Overdue = out at the lab and past its expected-back date.
  def lab_overdue?
    at_lab? && lab_due_on.present? && lab_due_on < Date.current
  end

  # Mark the procedure done. Records the completion date; fee snapshot was taken at create.
  def complete!(on: Date.current)
    update!(status: "completed", completed_date: on)
  end

  def fee
    fee_cents.to_i / 100.0
  end

  private

  # Snapshot the fee + VAT from the catalogue at the time of charting, so later
  # catalogue price changes never rewrite history.
  def snapshot_fee_and_vat
    return unless procedure_code
    self.fee_cents ||= procedure_code.default_fee_cents
    self.vat_treatment = procedure_code.vat_treatment if vat_treatment.blank?
  end
end
