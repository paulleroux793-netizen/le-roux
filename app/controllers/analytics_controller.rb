class AnalyticsController < ApplicationController
  def index
    page_data = dev_page_cache("analytics", "index") do
      {
        cancellation_stats: cancellation_stats,
        booking_stats: booking_stats,
        channel_stats: channel_stats,
        daily_bookings: daily_bookings,
        status_distribution: status_distribution,
      }
    end

    render inertia: "Analytics", props: page_data
  end

  private

  def cancellation_stats
    reasons = CancellationReason.group(:reason_category).count
    status_counts = Appointment.group(:status).count
    total_appointments = status_counts.values.sum
    total_cancelled = status_counts.fetch("cancelled", 0)

    {
      by_reason: CancellationReason::CATEGORIES.map { |cat|
        { category: cat, count: reasons[cat] || 0 }
      },
      total_cancelled: total_cancelled,
      cancellation_rate: calculate_rate(total_cancelled, total_appointments)
    }
  end

  def booking_stats
    now = Date.current
    last_30_days = (now - 30.days)..now

    status_counts = Appointment.where(created_at: last_30_days).group(:status).count
    total_bookings = status_counts.values.sum
    completed = status_counts.fetch("completed", 0)
    no_shows = status_counts.fetch("no_show", 0)
    conversion_total =
      status_counts.fetch("completed", 0) +
      status_counts.fetch("confirmed", 0) +
      status_counts.fetch("scheduled", 0)

    {
      total_bookings_30d: total_bookings,
      completed_30d: completed,
      no_shows_30d: no_shows,
      conversion_rate: calculate_rate(conversion_total, total_bookings)
    }
  end

  def channel_stats
    channel_counts = Conversation.group(:channel).count
    whatsapp = channel_counts.fetch("whatsapp", 0)
    voice = channel_counts.fetch("voice", 0)
    total = whatsapp + voice

    {
      whatsapp: whatsapp,
      voice: voice,
      whatsapp_pct: calculate_rate(whatsapp, total),
      voice_pct: calculate_rate(voice, total)
    }
  end

  def daily_bookings
    now = Date.current
    days = (now - 29.days)..now
    counts = Appointment
      .where(created_at: days.begin.beginning_of_day..days.end.end_of_day)
      .group("DATE(created_at)")
      .count

    days.map do |d|
      { date: d.strftime("%b %-d"), count: counts[d] || 0 }
    end
  end

  def status_distribution
    Appointment.group(:status).count.map { |status, count|
      { name: status.humanize, value: count }
    }
  end

  def calculate_rate(numerator, denominator)
    return 0 if denominator.zero?
    ((numerator.to_f / denominator) * 100).round(1)
  end
end
