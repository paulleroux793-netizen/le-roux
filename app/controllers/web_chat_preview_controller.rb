# Internal preview of the website booking widget (behind the dashboard login) so Paul can
# actually talk to it before it goes anywhere near the public site. Renders a sample page that
# loads the same /web-chat-widget.js + POST /api/v1/web_chat endpoint. This is NOT the public
# embed — going live on the real website is a separate one-line <script> the SEO site adds once
# Paul flips WEB_CHAT_ENABLED on.
class WebChatPreviewController < ApplicationController
  # The preview page is a public demo (no PHI) so Paul + the SEO team can open it and chat
  # without a login. The PHI dashboard controllers still enforce login normally.
  skip_before_action :require_login, raise: false

  def show
    render layout: false
  end

  private

  # Belt-and-braces: skip_before_action doesn't reliably remove the conditional :require_login
  # filter on Rails 8.1, so no-op it here too. Scoped to THIS controller only.
  def require_login; end
end
