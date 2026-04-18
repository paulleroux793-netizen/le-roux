class ApplicationController < ActionController::Base
  include InertiaRails::Controller

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

  def dev_page_cache(*parts, expires_in: 10.seconds)
    return yield unless Rails.env.development?

    Rails.cache.fetch(["dev-page-cache", *parts].join("/"),
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
  def safe_unread_count
    Rails.cache.fetch("notifications/unread_count", expires_in: 30.seconds) do
      Notification.unread.count
    end
  rescue ActiveRecord::StatementInvalid
    0
  end
end
