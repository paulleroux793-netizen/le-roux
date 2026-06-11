# GET /link_preview?url=... — server-side Open-Graph unfurl for the WhatsApp-style chat bubbles.
# Dashboard-only (inherits the app's auth). SSRF-guarded inside LinkPreview; always returns JSON
# ({} on any failure), never 500s.
class LinkPreviewsController < ApplicationController
  def show
    render json: LinkPreview.fetch(params[:url].to_s)
  end
end
