# A dashboard user — staff member who logs in individually once USER_AUTH_ENABLED is on.
# Roles: reception (default), dentist, admin. Passwords hashed with bcrypt.
class User < ApplicationRecord
  has_secure_password

  ROLES = %w[reception dentist admin].freeze

  before_validation { self.email = email.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :name,  presence: true
  validates :role,  inclusion: { in: ROLES }

  scope :active, -> { where(active: true) }

  ROLES.each { |r| define_method("#{r}?") { role == r } }

  # Dentists and admins can see/do more than reception (e.g. clinical notes, settings).
  def admin_or_dentist? = admin? || dentist?

  # What shows up in the audit trail.
  def to_audit = name.presence || email
end
