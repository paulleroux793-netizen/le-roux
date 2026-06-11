# Dependency-free error alerting — interim until a full Sentry/APM is wired (that
# needs a gem + image rebuild + DSN; see system/memory). This captures UNHANDLED
# exceptions, logs them as one structured JSON line ([ErrorAlert] …), and — only if
# ALERT_WEBHOOK_URL is set — POSTs a one-line summary to that webhook (Slack/Discord/
# ntfy-compatible {"text": …}). It RE-RAISES so Rails' normal error handling/500 page
# is completely unchanged, and the POST runs on a background thread so a slow/down
# webhook can never delay a request. No webhook URL => log-only (still useful: grep
# the logs for [ErrorAlert]). Zero behaviour change to existing flows.
require "net/http"
require "uri"
require "json"

class ErrorAlertMiddleware
  # Routing/format noise isn't worth paging on.
  IGNORE = [ "ActionController::RoutingError", "ActionController::UnknownFormat",
             "ActionController::BadRequest" ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue Exception => e # rubocop:disable Lint/RescueException — we re-raise immediately
    report(e, env) unless IGNORE.include?(e.class.name)
    raise
  end

  private

  def report(e, env)
    info = {
      ts:        Time.now.utc.iso8601,
      error:     e.class.name,
      message:   e.message.to_s[0, 300],
      method:    env["REQUEST_METHOD"],
      path:      env["PATH_INFO"],
      backtrace: Array(e.backtrace).first(5)
    }
    Rails.logger.error("[ErrorAlert] #{info.to_json}")

    url = ENV["ALERT_WEBHOOK_URL"].presence or return
    text = "\u{1F534} Ivory error: #{info[:error]} on #{info[:method]} #{info[:path]} — #{info[:message]}"
    Thread.new do
      uri  = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 3
      http.read_timeout = 3
      http.post(uri.request_uri, { text: text }.to_json, "Content-Type" => "application/json")
    rescue StandardError
      nil # never let alerting failure surface
    end
  end
end

Rails.application.config.middleware.use ErrorAlertMiddleware
