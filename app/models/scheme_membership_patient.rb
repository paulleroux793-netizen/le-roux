# Join: links a Patient (dependant or main member) to a SchemeMembership with their
# dependant code. Keeps the live `patients` table untouched.
class SchemeMembershipPatient < ApplicationRecord
  ROLES = %w[main_member dependant].freeze

  belongs_to :scheme_membership
  belongs_to :patient

  validates :role, inclusion: { in: ROLES }
  validates :patient_id, uniqueness: { scope: :scheme_membership_id }
end
