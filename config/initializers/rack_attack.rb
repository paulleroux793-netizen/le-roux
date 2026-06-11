# Rate limiting for the public, internet-facing patient intake endpoint.
# Defence-in-depth BEHIND Cloudflare's own edge rate limiting / WAF: even if an
# attacker reaches the origin, they can't brute-force tokens or hammer the form.
# The dashboard is not internet-reachable (host-locked + Cloudflare), so throttles
# deliberately target only /intake. Uses Rails.cache (solid_cache) as the store.
return unless defined?(Rack::Attack)

require "ipaddr"

class Rack::Attack
  # Never throttle the local network, container health checks, or the LAN/Tailscale dashboard.
  # NB: reception + Paul reach the dashboard over Tailscale (CGNAT 100.64.0.0/10), so those IPs
  # MUST be safelisted too — otherwise an active SPA session (many XHRs) trips dashboard/ip
  # (20/5min) and shows "Too many requests", breaking AI auto-fill + quick-add. 2026-06-08.
  TAILSCALE_CGNAT = IPAddr.new("100.64.0.0/10")
  safelist("local") do |req|
    ip = req.ip.to_s
    [ "127.0.0.1", "::1" ].include?(ip) || ip.start_with?("172.", "10.", "192.168.") ||
      (TAILSCALE_CGNAT.include?(ip) rescue false)
  end

  # Per-IP cap on the intake endpoint (a human filling a form makes few requests).
  throttle("intake/ip", limit: 40, period: 5 * 60) do |req|
    req.ip if req.path.start_with?("/intake")
  end

  # Per-token cap — a single tokenised link should never be hit many times. The shared
  # generic link "/intake/new" is exempt: it's not a secret to brute-force and is filled
  # by many different patients, so it must not share one counter (per-IP still applies).
  throttle("intake/token", limit: 25, period: 60 * 60) do |req|
    if req.path.start_with?("/intake/")
      tok = req.path.split("/intake/", 2).last.to_s[0, 80]
      tok.presence unless tok == "new"
    end
  end

  # A human fills ONE form; bots mass-submit. Cap actual SUBMISSIONS (the create/complete
  # PATCH/PUT/POST to /intake) hard, separately from page GETs, so the public /intake/new
  # link can't be abused to mass-create patient records and fire completion emails. Eight
  # per hour per IP still covers a family filling forms together on one connection.
  throttle("intake/submit", limit: 8, period: 60 * 60) do |req|
    req.ip if req.path.start_with?("/intake") && %w[PATCH PUT POST].include?(req.request_method)
  end

  # Brute-force protection on the LOGIN POST ONLY. The dashboard is now reached over
  # the PUBLIC tunnel (ivory.chalitaleroux.co.za) — reception + both surgeries share
  # one practice ISP IP — so the OLD blanket "dashboard/ip" cap (20 req/5min on every
  # non-intake path) throttled an active SPA session (the diary polls every 30s + many
  # XHRs) and showed "Too many requests", breaking live staff work (2026-06-11).
  # The dashboard already requires login (unauth paths just 302 → /login, cheap, no PHI),
  # so the only thing worth rate-limiting is password guessing. Cap the auth POST: a human
  # needs a handful of tries; a bot needs many. Authenticated dashboard use is NEVER throttled.
  throttle("login/ip", limit: 20, period: 5 * 60) do |req|
    req.ip if req.path == "/login" && req.request_method == "POST"
  end

  # Public website chat-booking endpoint (/api/v1/web_chat). Each visitor reaches the
  # origin as their own client IP (Cloudflare forwards it), so a per-IP cap throttles
  # abusers without affecting real visitors. 60 turns / 5 min is far more than a genuine
  # booking conversation needs, but stops a bot hammering the endpoint to run up AI cost
  # or mass-create bookings. The endpoint is also flag-gated (WEB_CHAT_ENABLED) + CORS-locked.
  throttle("web_chat/ip", limit: 60, period: 5 * 60) do |req|
    req.ip if req.path == "/api/v1/web_chat" && req.request_method == "POST"
  end

  # Friendly 429 instead of a stack trace.
  self.throttled_responder = lambda do |_req|
    [ 429, { "Content-Type" => "text/plain" },
      [ "Too many requests. Please wait a minute and try again.\n" ] ]
  end
end
