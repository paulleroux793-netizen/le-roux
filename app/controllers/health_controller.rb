# Readiness probe for EXTERNAL uptime monitors (UptimeRobot / healthchecks.io / etc).
# Rails' built-in /up only proves the process booted; this also checks the DB so an
# external monitor can page when the app is up but the database is unreachable.
#
# Inherits ActionController::Base directly (like the webhook controllers) so it
# BYPASSES the dashboard HTTP-basic-auth — it exposes NO patient data, only status,
# and a monitor must reach it without credentials. Cheap: one `SELECT 1`.
class HealthController < ActionController::Base
  def show
    t0         = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    db         = database_ok?
    db_ms      = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1)
    pending    = pending_jobs
    backup_age = backup_age_hours

    # Degraded if the DB is down/slow, queue work is badly backed up (jobs not draining =
    # WhatsApp replies / reminders silently stuck), OR the last backup is stale (>36h =
    # a silently-failing nightly backup, the kind you only discover when you need it).
    healthy = db && db_ms < 2000 && (pending.nil? || pending < 500) && (backup_age.nil? || backup_age <= 36)

    render json: {
      status:            healthy ? "ok" : "degraded",
      db:                db,
      db_latency_ms:     db_ms,
      queue_pending:     pending,
      backup_age_hours:  backup_age,
      time:              Time.now.utc.iso8601,
      version:           ENV["GIT_SHA"].to_s[0, 8].presence
    }, status: (healthy ? :ok : :service_unavailable)
  end

  private

  def database_ok?
    ActiveRecord::Base.connection.execute("SELECT 1") && true
  rescue StandardError
    false
  end

  # Hours since the last successful nightly backup, from the marker rig_backup.sh drops in
  # tmp/ (the backups dir itself is outside the container mount). nil if no marker yet.
  def backup_age_hours
    path = Rails.root.join("ops/last_backup.json")
    return nil unless File.exist?(path)

    at = Time.parse(JSON.parse(File.read(path))["at"])
    ((Time.now - at) / 3600.0).round(1)
  rescue StandardError
    nil
  end

  # Solid Queue backlog (unfinished jobs). A growing backlog means background work
  # (WhatsApp sends, reminders) isn't draining. nil if the queue isn't available.
  def pending_jobs
    return nil unless defined?(SolidQueue::Job)

    SolidQueue::Job.where(finished_at: nil).count
  rescue StandardError
    nil
  end
end
