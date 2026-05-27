# Daily reconciliation dashboard — the learning-loop view that compares
# Elixir's actual delivery to Ivory's predicted delivery and surfaces
# specific actionable improvements.
#
# Paul's framing (2026-05-27):
#   "At the end of the day, looking at all your possible deliverables,
#   you can say 'This is what they actually delivered today.' Let's
#   compare it with what the Ivory system would have delivered,
#   and what improvements can we make to Ivory so it can also get that
#   result?"
class ReconciliationController < ApplicationController
  def index
    target_date = parse_date(params[:date]) || Date.current
    payload = DailyReconciliationService.new(target_date).call.to_h

    render inertia: "Reconciliation", props: {
      reconciliation: payload,
      navigation: {
        prev_date: (target_date - 1.day).iso8601,
        next_date: (target_date + 1.day).iso8601,
        today:     Date.current.iso8601
      },
      recent_imports: ElixirMirrorImport.recent(10).map { |i|
        {
          id:           i.id,
          file_name:    i.file_name,
          file_kind:    i.file_kind,
          status:       i.status,
          rows_parsed:  i.rows_parsed,
          rows_inserted: i.rows_inserted,
          error_message: i.error_message,
          started_at:   i.started_at&.iso8601,
          finished_at:  i.finished_at&.iso8601
        }
      }
    }
  end

  # POST /reconciliation/scan — kick off an Elixir mirror scan in-process.
  # In production this becomes a background job; for now a synchronous
  # button so Paul can refresh on demand from the dashboard.
  def scan
    results = ElixirMirror::Importer.scan_default_locations
    redirect_to reconciliation_path(date: params[:date]),
                notice: "Scanned #{results.size} files."
  rescue StandardError => e
    redirect_to reconciliation_path(date: params[:date]),
                alert: "Scan error: #{e.class}: #{e.message}"
  end

  private

  def parse_date(s)
    return nil if s.blank?
    Date.parse(s)
  rescue ArgumentError
    nil
  end
end
