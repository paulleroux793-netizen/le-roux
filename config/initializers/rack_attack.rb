# Rate limiting for the public, internet-facing patient intake endpoint.
# Defence-in-depth BEHIND Cloudflare's own edge rate limiting / WAF: even if an
# attacker reaches the origin, they can't brute-force tokens or hammer the form.
# The dashboard is not internet-reachable (host-locked + Cloudflare), so throttles
# deliberately target only /intake. Uses Rails.cache (solid_cache) as the store.
return unless defined?(Rack::Attack)

class Rack::Attack
  # Never throttle the local network, container health checks, or the LAN dashboard.
  safelist("local") do |req|
    [ "127.0.0.1", "::1" ].include?(req.ip) || req.ip.to_s.start_with?("172.", "10.", "192.168.")
  end

  # Per-IP cap on the intake endpoint (a human filling a form makes few requests).
  throttle("intake/ip", limit: 40, period: 5 * 60) do |req|
    req.ip if req.path.start_with?("/intake")
  end

  # Per-token cap — a single tokenised link should never be hit many times.
  throttle("intake/token", limit: 25, period: 60 * 60) do |req|
    if req.path.start_with?("/intake/")
      req.path.split("/intake/", 2).last.to_s[0, 80].presence
    end
  end

  # Friendly 429 instead of a stack trace.
  self.throttled_responder = lambda do |_req|
    [ 429, { "Content-Type" => "text/plain" },
      [ "Too many requests. Please wait a minute and try again.\n" ] ]
  end
end
