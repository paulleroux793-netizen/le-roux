module QueryCounter
  IGNORED_SQL_PATTERNS = [
    /\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)\b/i,
    /\A(?:PRAGMA|SHOW)\b/i
  ].freeze

  def capture_queries
    queries = []

    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      payload = args.last
      next if payload[:name] == "SCHEMA"
      next if payload[:cached]

      sql = payload[:sql].to_s.squish
      next if IGNORED_SQL_PATTERNS.any? { |pattern| sql.match?(pattern) }

      queries << sql
    end

    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end

RSpec.configure do |config|
  config.include QueryCounter
end
