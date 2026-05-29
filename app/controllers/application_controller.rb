class ApplicationController < ActionController::Base
  include InertiaRails::Controller

  # Minimum-viable auth: HTTP basic auth on the dashboard.
  # The dashboard exposes patient PII so it MUST NOT be publicly browsable.
  # This is a stop-gap until Devise + per-user roles land in a follow-up PR;
  # until then a single shared password gates the whole dashboard.
  #
  # Webhook controllers extend ActionController::API directly (NOT this
  # class) so Twilio inbounds bypass the basic-auth check and continue to
  # be authenticated by X-Twilio-Signature only.
  #
  # The /voice/audio/* endpoint, however, IS an ApplicationController (it
  # renders cached blobs, not API). Twilio fetches those URLs anonymously
  # via TwiML <Play>, so it must stay public too — otherwise Twilio gets a
  # 401 on the audio fetch and the caller hears "an application error has
  # occurred". It exposes no PII (only μ-law TTS bytes keyed by an
  # unguessable SHA256 hash), so excluding it from the gate is safe.
  #
  # Configure via Railway env:
  #   DASHBOARD_USERNAME (e.g. "reception")
  #   DASHBOARD_PASSWORD (a strong shared password)
  # Skipping the env vars (e.g. in dev/test) leaves the dashboard open —
  # production deploys SHOULD set both before going live.
  http_basic_authenticate_with(
    name:     ENV["DASHBOARD_USERNAME"].to_s,
    password: ENV["DASHBOARD_PASSWORD"].to_s,
    if:       -> { dashboard_basic_auth_required? }
  )

  # Phase 9.6 sub-area #6 — shared Inertia props.
  #
  # Exposes the unread notification count to every Inertia page so
  # the navbar bell badge stays accurate on every navigation without
  # needing a separate fetch. Evaluated per-request inside the block.
  inertia_share do
    {
      unread_notifications_count: safe_unread_count,
      ui_language: session[:ui_language].presence || "en"
    }
  end

  private

  # Whether the dashboard basic-auth gate applies to this request.
  # Returns false for the public /voice/audio/* endpoint (fetched
  # anonymously by Twilio's TwiML <Play>) so those audio blobs stay
  # reachable even when DASHBOARD_USERNAME/PASSWORD are configured.
  def dashboard_basic_auth_required?
    return false if request.path.start_with?("/voice/audio")

    ENV["DASHBOARD_USERNAME"].present? && ENV["DASHBOARD_PASSWORD"].present?
  end

  def dev_page_cache(*parts, expires_in: 10.seconds)
    return yield unless Rails.env.development?

    Rails.cache.fetch([ "dev-page-cache", *parts ].join("/"),
      expires_in: expires_in,
      race_condition_ttl: 1.second) do
      yield
    end
  end

  def expire_dev_page_cache(prefix)
    return unless Rails.env.development?

    Rails.cache.delete_matched(/^dev-page-cache\/#{Regexp.escape(prefix)}/)
  end

  # Defensive wrapper: if the notifications table isn't present yet
  # (fresh dev clone before `db:migrate`) we shouldn't blow up every
  # page render.
  def audit_performer
    "Staff"
  end

  def safe_unread_count
    Rails.cache.fetch("notifications/unread_count", expires_in: 30.seconds) do
      Notification.unread.count
    end
  rescue ActiveRecord::StatementInvalid
    0
  end
end
