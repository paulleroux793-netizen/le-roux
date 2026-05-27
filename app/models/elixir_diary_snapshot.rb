# Read-only snapshot of one row from an Elixir-exported daily diary PDF.
# Stays separate from Ivory's own `appointments` table during the
# data-gathering phase. The comparison view JOINs the two by date +
# patient name / account code.
class ElixirDiarySnapshot < ApplicationRecord
  # Pessimistic find — never trust upstream identity until we reconcile.
  scope :for_date,    ->(d) { where(diary_date: d) }
  scope :for_dentist, ->(name) { where(dentist: name) }
  scope :by_account,  ->(code) { where(account_code: code) }

  def dentist_short
    case dentist.to_s
    when /CHALITA/i then "Dr Chalita"
    when /ELISKA/i  then "Dr Eliska"
    else dentist.to_s.sub(/^DR\s+/i, "Dr ").titleize.presence || "Unknown"
    end
  end
end
