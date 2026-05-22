# A billable procedure in the catalogue (SADA/practice tariff code).
# VAT: medically-necessary dental treatment is zero-rated (VAT Act s12(c));
# purely cosmetic (e.g. whitening) is standard-rated 15%.
class ProcedureCode < ApplicationRecord
  VAT_TREATMENTS = %w[zero_rated standard].freeze
  STANDARD_VAT_RATE = 0.15

  has_many :fee_schedule_items, dependent: :destroy
  has_many :treatment_macro_items, dependent: :nullify

  validates :code, presence: true, uniqueness: true
  validates :description, presence: true
  validates :vat_treatment, inclusion: { in: VAT_TREATMENTS }

  scope :active, -> { where(active: true) }

  def default_fee
    default_fee_cents.to_i / 100.0
  end

  # The medical-aid (Discovery) rate, if known. Self portion = practice fee − medical.
  def medical_fee
    medical_fee_cents.to_i / 100.0
  end

  def standard_rated?
    vat_treatment == "standard"
  end
end
