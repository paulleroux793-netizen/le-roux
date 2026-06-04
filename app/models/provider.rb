# A dentist who has their own diary column (Dr Chalita le Roux, Dr Eliska Robinson).
# Mirrors the Elixir "Provider" on each account + the per-dentist diary columns.
class Provider < ApplicationRecord
  has_many :appointments, dependent: :nullify
  has_many :doctor_schedules, dependent: :destroy
  has_many :calendar_notes, dependent: :nullify

  validates :name, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  # Short label for the diary column header / account "Provider" field.
  def display_name
    short_name.presence || name
  end
end
