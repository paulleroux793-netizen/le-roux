# Atomic, gap-free document numbering for tax-compliant invoice/estimate/statement numbers.
# Uses a row lock so concurrent requests can never collide or skip a number.
class DocumentSequence < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Returns the next integer for `key`, incremented atomically.
  def self.next_value(key)
    transaction do
      seq = lock("FOR UPDATE").find_by(key: key) || create!(key: key, current_value: 0).tap { |s| s.lock! }
      seq.update!(current_value: seq.current_value + 1)
      seq.current_value
    end
  end

  # Formatted document number, e.g. "INV-2026-000123".
  def self.next_number(key, prefix:, year: Date.current.year, width: 6)
    format("%s-%d-%0*d", prefix, year, width, next_value(key))
  end
end
