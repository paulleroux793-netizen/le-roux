# A versioned form template (medical history, consent, etc.) sent to patients over WhatsApp.
class FormTemplate < ApplicationRecord
  has_many :form_submissions, dependent: :restrict_with_error

  validates :key, presence: true
  validates :name, presence: true
  validates :version, uniqueness: { scope: :key }

  scope :active, -> { where(active: true) }

  # Latest active version for a key.
  def self.latest(key)
    where(key: key, active: true).order(version: :desc).first
  end
end
