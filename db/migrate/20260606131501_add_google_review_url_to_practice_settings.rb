class AddGoogleReviewUrlToPracticeSettings < ActiveRecord::Migration[8.1]
  # Google review link (from the DR CHALITA SEO project's GBP). When set, the
  # patient page shows a "Request review" action that opens a pre-filled
  # WhatsApp message with the link for reception to send post-visit.
  def change
    add_column :practice_settings, :google_review_url, :string
  end
end
