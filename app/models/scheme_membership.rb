# A medical-aid membership contract: a main member on a scheme/plan, with dependants.
# Used only to print correct details on the self-claim statement.
class SchemeMembership < ApplicationRecord
  belongs_to :medical_scheme
  belongs_to :main_member_patient, class_name: "Patient", optional: true
  has_many :scheme_membership_patients, dependent: :destroy
  has_many :patients, through: :scheme_membership_patients

  validates :member_number, presence: true

  def active?(on = Date.current)
    (effective_from.nil? || effective_from <= on) &&
      (effective_to.nil? || effective_to >= on)
  end
end
