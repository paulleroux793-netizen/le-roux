# Server-side Open-Graph "unfurl" for the WhatsApp-style chat bubbles: given a URL, fetch it and
# return {title,image,description,host} so the UI can show a preview card (browsers can't fetch
# cross-origin). SSRF-GUARDED — every hop's host must resolve only to PUBLIC IPs, or we refuse to
# fetch. Never raises: returns {} on any failure. Cached 1h.
require "net/http"
require "resolv"
require "ipaddr"
require "uri"

class LinkPreview
  MAX_REDIRECTS = 2
  TIMEOUT       = 5
  MAX_BODY      = 512 * 1024
  UA            = "Mozilla/5.0 (compatible; IvoryLinkPreview/1.0; +https://chalitaleroux.co.za)".freeze

  # Private / loopback / link-local / unique-local / unspecified — never fetch these.
  BLOCKED = [
    "0.0.0.0/8", "10.0.0.0/8", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12",
    "192.168.0.0/16", "::1/128", "fc00::/7", "fe80::/10"
  ].map { |c| IPAddr.new(c) }.freeze

  def self.fetch(url)
    return {} if url.to_s.strip.empty?
    Rails.cache.fetch("lp:#{url}", expires_in: 1.hour) { (new(url).preview rescue {}) || {} }
  end

  def initialize(url) = (@url = url.to_s.strip)

  def preview
    body, final_url = get_with_guard(@url, 0)
    return {} unless body

    doc = Nokogiri::HTML(body)
    og  = ->(p) { doc.at_css("meta[property='og:#{p}']")&.[]("content") || doc.at_css("meta[name='og:#{p}']")&.[]("content") }
    {
      title:       (og.call("title") || doc.at_css("title")&.text).to_s.strip.presence,
      image:       og.call("image").to_s.strip.presence,
      description: (og.call("description") || doc.at_css("meta[name='description']")&.[]("content")).to_s.strip.presence,
      host:        (URI.parse(final_url).host rescue nil)
    }.compact
  end

  private

  # All resolved addresses for the host must be public, or it's unsafe.
  def public_host?(host)
    addrs = Resolv.getaddresses(host.to_s)
    return false if addrs.empty?
    addrs.all? do |a|
      ip = (IPAddr.new(a) rescue nil)
      ip && BLOCKED.none? { |r| r.include?(ip) }
    end
  rescue StandardError
    false
  end

  def get_with_guard(url, depth)
    return [ nil, url ] if depth > MAX_REDIRECTS
    uri = URI.parse(url)
    return [ nil, url ] unless uri.is_a?(URI::HTTP)        # http / https only
    return [ nil, url ] unless public_host?(uri.host)       # SSRF guard (re-checked every hop)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.is_a?(URI::HTTPS)
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT
    res = http.request(Net::HTTP::Get.new(uri, "User-Agent" => UA, "Accept" => "text/html"))

    case res
    when Net::HTTPRedirection
      loc = res["location"]
      return [ nil, url ] if loc.to_s.empty?
      get_with_guard(URI.join(url, loc).to_s, depth + 1)
    when Net::HTTPSuccess
      [ res.body.to_s[0, MAX_BODY], url ]
    else
      [ nil, url ]
    end
  rescue StandardError => e
    Rails.logger.warn("[LinkPreview] #{url}: #{e.class}: #{e.message}")
    [ nil, url ]
  end
end
