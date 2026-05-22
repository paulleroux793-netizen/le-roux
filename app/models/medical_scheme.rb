# A medical aid scheme. Reference data ONLY — the practice never submits claims to it.
# Printed on the patient's statement so they can claim back themselves.
class MedicalScheme < ApplicationRecord
  has_many :scheme_memberships, dependent: :restrict_with_error

  validates :name, presence: true
  validates :scheme_code, uniqueness: true, allow_nil: true

  scope :active, -> { where(active: true) }
end
