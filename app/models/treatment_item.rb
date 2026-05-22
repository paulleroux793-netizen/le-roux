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
