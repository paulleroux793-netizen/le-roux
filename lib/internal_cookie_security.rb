# Strips the `Secure` attribute from Set-Cookie responses for INTERNAL hosts only
# (LAN 10.0.0.x, Tailscale 100.x, localhost). Reception reaches the dashboard over plain
# HTTP on those, but config.assume_ssl=true (needed so the Cloudflare tunnel's webhook
# signature validation + URL generation see https) makes Rails mark the session + XSRF
# cookies Secure — which browsers then DROP over HTTP, so per-user login can never hold a
# session. We must keep assume_ssl (Twilio webhook depends on it), so instead we drop the
# Secure flag on the way out for internal hosts. Public/tunnel hosts are left untouched.
class InternalCookieSecurity
  INTERNAL = /\A(?:10\.0\.0\.|100\.|127\.0\.0\.1|localhost|192\.168\.)/

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    host = env["HTTP_HOST"].to_s.split(":").first
    sc_key = host && INTERNAL.match?(host) && headers.keys.find { |k| k.to_s.casecmp?("set-cookie") }
    if sc_key
      cookies = headers[sc_key]
      list = cookies.is_a?(Array) ? cookies : cookies.to_s.split("\n")
      list = list.map { |c| c.to_s.gsub(/;\s*secure\b/i, "") }
      headers[sc_key] = (list.size == 1 ? list.first : list)
    end
    [ status, headers, body ]
  end
end
