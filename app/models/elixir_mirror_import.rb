# Record of a single Elixir-mirror ingest run (one file → one record).
# Lets us skip re-importing a file whose sha256 already imported,
# and gives us a per-file audit trail for the comparison dashboard.
class ElixirMirrorImport < ApplicationRecord
  KINDS = %w[diary transaction_report estimates_listing].freeze

  scope :diary,         -> { where(file_kind: "diary") }
  scope :transactions,  -> { where(file_kind: "transaction_report") }
  scope :estimates,     -> { where(file_kind: "estimates_listing") }
  scope :recent,        ->(n=20) { order(started_at: :desc).limit(n) }
  scope :succeeded,     -> { where(status: "succeeded") }
  scope :failed,        -> { where(status: "failed") }
end
