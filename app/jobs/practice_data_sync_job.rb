# Background sync of the read-only mirrors that feed the Daily Reconciliation
# dashboard and the patient Imaging tab:
#   * Elixir exports (diary + transaction PDFs + Estimates XLSX) -> snapshot tables
#   * SIDEXIS "5. Sidexis 4 Scans" folder                        -> imaging_studies
#
# Idempotent: an already-seen file (sha256 for Elixir, source key for SIDEXIS) is
# a no-op, so this is safe to run on a schedule (see config/recurring.yml). Each
# source is isolated — one failing does NOT abort the other. READ-ONLY on Dr
# Chalita's data folder throughout (the folder is mounted :ro in any case).
#
# Triggers:
#   * Recurring (production) — hourly, both sources. See config/recurring.yml.
#   * Manual — the "Scan" buttons on /reconciliation (elixir) and /imaging (sidexis)
#     enqueue this instead of blocking the request.
class PracticeDataSyncJob < ApplicationJob
  queue_as :default

  def perform(sources: %w[elixir sidexis])
    sources = Array(sources).map(&:to_s)
    Rails.logger.info("[PracticeDataSyncJob] starting sync for: #{sources.join(', ')}")

    if sources.include?("elixir")
      run_source("elixir") do
        results  = ElixirMirror::Importer.scan_default_locations
        inserted = results.sum { |r| r.rows_inserted.to_i }
        "#{results.size} files seen, #{inserted} rows imported/updated"
      end
    end

    if sources.include?("sidexis")
      run_source("sidexis") do
        r = ImagingImportService.scan_sidexis_folder
        "#{r.created} new studies (#{r.matched} matched, #{r.needs_match} need match), #{r.skipped} unchanged"
      end
    end
  end

  private

  # Run one source, log its outcome, and SWALLOW its error so the other source
  # still runs and the job itself doesn't trip ApplicationJob's global re-raise.
  def run_source(name)
    started = Time.current
    summary = yield
    Rails.logger.info("[PracticeDataSyncJob] #{name} OK in #{(Time.current - started).round(1)}s — #{summary}")
  rescue StandardError => e
    Rails.logger.error("[PracticeDataSyncJob] #{name} FAILED: #{e.class}: #{e.message}")
  end
end
