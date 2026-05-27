# Read-only snapshot of one row from the Estimates listing.xlsx that Shaune
# (or her replacement) maintains by hand.
class ElixirEstimateSnapshot < ApplicationRecord
  scope :for_account, ->(code) { where(account_code: code) }
  scope :recent,      ->(n=50) { order(date_sent: :desc).limit(n) }
  scope :outstanding, -> { where(legend: nil) }

  def short_update_note
    update_note.to_s.lines.first(2).join.strip.slice(0, 200)
  end
end
