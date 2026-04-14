class NotificationsController < ApplicationController
  # Phase 9.6 sub-area #6 — Notification System.
  #
  # JSON-only controller that powers the bell dropdown in the navbar.
  # Returns the N most recent notifications plus an unread count;
  # also exposes endpoints to mark one or all as read.
  #
  # Kept as JSON (not Inertia) so the dropdown can fetch on open
  # without a full-page transition.
  LIST_LIMIT = 20

  def index
    notifications = Notification.recent.limit(LIST_LIMIT)
    render json: {
      notifications: notifications.map { |n| notification_props(n) },
      unread_count: Notification.unread.count
    }
  end

  # PATCH /notifications/:id/read
  def mark_read
    notification = Notification.find(params[:id])
    notification.mark_read!
    Notification.expire_unread_count_cache!
    render json: { ok: true, unread_count: Notification.unread.count }
  end

  # POST /notifications/mark_all_read
  def mark_all_read
    Notification.unread.update_all(read_at: Time.current)
    Notification.expire_unread_count_cache!
    render json: { ok: true, unread_count: 0 }
  end

  private

  def notification_props(n)
    {
      id: n.id,
      category: n.category,
      level: n.level,
      title: n.title,
      body: n.body,
      url: n.url,
      read: n.read?,
      created_at: n.created_at.iso8601
    }
  end
end
