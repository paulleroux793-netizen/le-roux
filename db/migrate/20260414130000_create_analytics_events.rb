class CreateAnalyticsEvents < ActiveRecord::Migration[8.0]
  # Phase 11 — lightweight event capture table.
  #
  # Domain metrics (bookings, cancellations, confirmation outcomes,
  # channel mix) are all derivable from existing domain tables and
  # live in AnalyticsMetricsService. This table exists for the
  # things that *can't* be recovered after the fact:
  #
  #   - page views ("receptionist opened /analytics at 09:12")
  #   - search queries ("searched for 'emily'")
  #   - imports ("imported 12 historical chats")
  #   - reminder sends / replies / audit-style UI actions
  #
  # The payload is free-form JSONB so new event types can be
  # captured without a schema change. The index is on
  # (event_type, occurred_at) because the common access pattern is
  # "recent events of type X in date range" — that's also what the
  # recent-events widget on the analytics page queries.
  def change
    create_table :analytics_events do |t|
      t.string   :event_type, null: false
      t.jsonb    :payload,    null: false, default: {}
      t.datetime :occurred_at, null: false
      t.string   :request_id
      t.string   :session_id

      t.timestamps
    end

    add_index :analytics_events, [ :event_type, :occurred_at ]
    add_index :analytics_events, :occurred_at
  end
end
