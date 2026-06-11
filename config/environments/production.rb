require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Railway terminates SSL at the proxy level.
  config.assume_ssl = true
  config.force_ssl = true

  # LAN access is plain HTTP (reception PCs on 10.0.0.x). Keep assume_ssl so the
  # Cloudflare webhook tunnel still generates correct https URLs, but DISABLE
  # HSTS: otherwise the 2-year Strict-Transport-Security header poisons LAN
  # browsers into forcing HTTPS on http://10.0.0.125:3000 → ERR_SSL_PROTOCOL_ERROR
  # (Chrome then can't reach the plain-HTTP rig at all). 2026-06-05.
  # secure_cookies:false — assume_ssl marks the session + CSRF cookies `Secure`, but LAN/
  # Tailscale access is plain HTTP, so browsers DROP them → per-user login can never hold a
  # session (the shared HTTP-basic password didn't need cookies, so this only surfaced once
  # USER_AUTH_ENABLED went on). Dashboard is internal-only (the public tunnel blocks it), and
  # cookies stay httponly + samesite=lax, so dropping the Secure flag is safe. 2026-06-08.
  config.ssl_options = { hsts: false, secure_cookies: false }

  # ...and the secure flag also comes from request.ssl? (assume_ssl), which secure_cookies:false
  # doesn't touch — so a middleware strips `Secure` from Set-Cookie for internal LAN/Tailscale
  # http hosts (the dashboard), keeping it for the public tunnel. Lets per-user login hold a session.
  require_relative "../../lib/internal_cookie_security"
  config.middleware.insert_before 0, InternalCookieSecurity

  # The CSRF *origin* check compares the Origin header to base_url, but assume_ssl
  # forces base_url to https while LAN/Tailscale access is plain http → every write
  # 422s ("Origin didn't match"). The authenticity TOKEN still fully protects
  # against CSRF, so disable the proxy-brittle origin check. 2026-06-05.
  config.action_controller.forgery_protection_origin_check = false

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "localhost") }

  # SMTP via ENV vars. Set SMTP_ADDRESS, SMTP_USER_NAME, SMTP_PASSWORD in Railway.
  # If SMTP_ADDRESS is not set, emails are logged to STDOUT (development-style fallback).
  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.smtp_settings = {
      address:              ENV.fetch("SMTP_ADDRESS"),
      port:                 ENV.fetch("SMTP_PORT", 587).to_i,
      user_name:            ENV.fetch("SMTP_USER_NAME", nil),
      password:             ENV.fetch("SMTP_PASSWORD", nil),
      authentication:       :plain,
      enable_starttls_auto: true,
      # Bounded so a slow/unreachable mail server can never hang a request that sends
      # mail synchronously (the intake completion email sends inline on submit).
      open_timeout:         10,
      read_timeout:         15
    }
  else
    config.action_mailer.delivery_method = :logger
    config.action_mailer.raise_delivery_errors = false
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
