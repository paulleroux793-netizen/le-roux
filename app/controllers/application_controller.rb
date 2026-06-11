class ApplicationController < ActionController::Base
  include InertiaRails::Controller

  # Defence-in-depth: the dashboard (everything inheriting this controller) must
  # NEVER be served on the public intake hostname. The patient form lives in
  # IntakesController < PublicController (not this class), so it is unaffected.
  # Cloudflare also blocks non-/intake paths on that host; this is the app-layer
  # backstop. No-op unless INTAKE_PUBLIC_HOST is set (i.e. only once a tunnel exists).
  before_action :block_public_host

  def block_public_host
    public_host = ENV["INTAKE_PUBLIC_HOST"].presence
    head :not_found if public_host && request.host.to_s.casecmp?(public_host)
  end

  # Per-user session auth (only when USER_AUTH_ENABLED is truthy). It coexists with the
  # HTTP-basic auth below: exactly one is ever active — the basic auth no-ops when user
  # auth is on (see dashboard_auth_required?). Flag OFF = nothing here runs = unchanged.
  before_action :require_login, if: :user_auth_enabled?

  # Minimum-viable auth: HTTP basic auth on the dashboard.
  # The dashboard exposes patient PII so it MUST NOT be publicly browsable.
  # This is a stop-gap until Devise + per-user roles land in a follow-up PR;
  # until then a single shared password gates the whole dashboard.
  #
  # Webhook controllers extend ActionController::API directly (NOT this
  # class) so Twilio inbounds bypass the basic-auth check and continue to
  # be authenticated by X-Twilio-Signature only.
  #
  # Configure via Railway env:
  #   DASHBOARD_USERNAME (e.g. "reception")
  #   DASHBOARD_PASSWORD (a strong shared password)
  # Skipping the env vars (e.g. in dev/test) leaves the dashboard open —
  # production deploys SHOULD set both before going live.
  # Password is required from OUTSIDE the practice (Tailscale / off-site), but NOT
  # when accessed on the practice LAN — reception + surgery PCs reach Ivory at the
  # rig's private-LAN IP (e.g. http://10.0.0.125:3000) and should not be prompted.
  # Trust is by the host the client used: a bare private-LAN IP = the practice
  # network (no password); a Tailscale IP (100.64/10) or a public hostname still
  # requires the password. (Paul's requirement, 2026-06-05.)
  http_basic_authenticate_with(
    name:     ENV["DASHBOARD_USERNAME"].to_s,
    password: ENV["DASHBOARD_PASSWORD"].to_s,
    if:       -> { dashboard_auth_required? }
  )

  # CSRF on the trusted practice LAN: the app assumes HTTPS (assume_ssl, for the
  # Cloudflare tunnel) but the LAN is served over plain HTTP — so the CSRF origin
  # check sees Origin=http vs base_url=https and rejects EVERY write (set_status,
  # drag-move, copy/paste, booking all 422'd). The LAN is already trusted + password
  # -free, so skip forgery protection there only. Tailscale + public hosts (and the
  # signature-checked webhooks, which aren't under this controller) still enforce it.
  skip_before_action :verify_authenticity_token, if: :csrf_exempt_network?

  # assume_ssl (kept for the Cloudflare webhook tunnel) makes redirect_to emit
  # `https://` Location headers. LAN + Tailscale clients reach the rig over plain
  # http, so following an https redirect dies with ERR_SSL_PROTOCOL_ERROR — this
  # silently broke "Create patient" (a redirect_to action). Downgrade the redirect
  # scheme to http for those private networks only; public/tunnel requests are
  # untouched, so webhook signature validation still sees https.
  after_action :downgrade_redirect_scheme_for_private_network

  # Phase 9.6 sub-area #6 — shared Inertia props.
  #
  # Exposes the unread notification count to every Inertia page so
  # the navbar bell badge stays accurate on every navigation without
  # needing a separate fetch. Evaluated per-request inside the block.
  inertia_share do
    {
      unread_notifications_count: safe_unread_count,
      ui_language: session[:ui_language].presence || "en",
      current_user: current_user && { id: current_user.id, name: current_user.name, role: current_user.role }
    }
  end

  private

  # Require the dashboard password unless the request is from the trusted practice
  # LAN. No creds configured (dev/test) => never prompt.
  def dashboard_auth_required?
    return false if user_auth_enabled? # per-user session auth replaces the shared password
    return false if ENV["DASHBOARD_USERNAME"].blank? || ENV["DASHBOARD_PASSWORD"].blank?

    !on_trusted_lan?
  end

  # Per-user auth is OFF unless USER_AUTH_ENABLED is explicitly truthy — so the live
  # dashboard keeps its current shared-password behaviour until Paul flips the flag.
  def user_auth_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV["USER_AUTH_ENABLED"]) == true
  end

  def current_user
    return nil unless user_auth_enabled?

    @current_user ||= User.find_by(id: session[:user_id])
  end
  helper_method :current_user

  # Gate every dashboard request behind a login (only active when the flag is on; the
  # login + health + webhook endpoints opt out so there's no redirect loop).
  def require_login
    return if current_user

    session[:return_to] = request.fullpath if request.get?
    redirect_to login_path
  end

  # Admin-only gate for sensitive actions (e.g. writing off debt). A no-op until per-user
  # auth is live; once it is, only admins pass. Returns false (and redirects) when blocked.
  def require_admin!
    return true unless user_auth_enabled?
    return true if current_user&.admin?

    redirect_back fallback_location: root_path, alert: "That action is restricted to admins.", status: :see_other
    false
  end

  # True when accessed via a private-LAN IP host (the practice network). Tailscale
  # IPs (100.64.0.0/10) and public hostnames are NOT trusted and still need the
  # password. Host-based because Docker port-publishing masks the real source IP.
  def on_trusted_lan?
    host = request.host.to_s
    host.match?(/\A(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\z/)
  end

  # CSRF is skipped on any authenticated PRIVATE network — the LAN AND the
  # Tailscale tailnet (100.64.0.0/10). Over their plain-http transport the
  # assume_ssl `Secure` CSRF cookie isn't sent, so the token can't round-trip and
  # every write would 422. Tailscale STILL requires the password (auth uses
  # on_trusted_lan?, not this). Public hosts + signature-checked webhooks unaffected.
  def csrf_exempt_network?
    on_trusted_lan? || on_tailscale?
  end

  def on_tailscale?
    request.host.to_s.match?(/\A100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}\z/)
  end

  def downgrade_redirect_scheme_for_private_network
    return unless csrf_exempt_network?
    loc = response.headers["Location"]
    response.headers["Location"] = loc.sub(/\Ahttps:/i, "http:") if loc&.match?(/\Ahttps:/i)
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
    current_user&.to_audit || "Staff"
  end

  def safe_unread_count
    Rails.cache.fetch("notifications/unread_count", expires_in: 30.seconds) do
      Notification.unread.count
    end
  rescue ActiveRecord::StatementInvalid
    0
  end
end
