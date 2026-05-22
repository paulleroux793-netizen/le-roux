class CalendarNotesController < ApplicationController
  # Diary reminders/notes — created and moved from the calendar, separate
  # from patient appointments. All actions redirect_back so the user stays
  # on whichever calendar view they were on (full-screen /calendar or the
  # dashboard /appointments list).

  def create
    starts_at = parse_time(note_params[:starts_at])
    ends_at   = parse_time(note_params[:ends_at]) || (starts_at && starts_at + 30.minutes)

    note = CalendarNote.new(starts_at: starts_at, ends_at: ends_at, note: note_params[:note])
    if note.save
      expire_calendar_caches!
      AuditService.log(
        action: "calendar_note.created",
        summary: "Added diary reminder \"#{note.note.truncate(60)}\" on #{note.starts_at.strftime('%-d %b at %H:%M')}",
        resource: note,
        performed_by: audit_performer,
        ip_address: request.remote_ip
      )
      redirect_back fallback_location: appointments_path, notice: "Reminder added", status: :see_other
    else
      redirect_back fallback_location: appointments_path,
        alert: note.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def update
    note = CalendarNote.find(params[:id])
    attrs = {}
    attrs[:note]      = note_params[:note] if note_params.key?(:note)
    attrs[:done]      = ActiveModel::Type::Boolean.new.cast(note_params[:done]) if note_params.key?(:done)
    if note_params[:starts_at].present?
      attrs[:starts_at] = parse_time(note_params[:starts_at])
      attrs[:ends_at]   = parse_time(note_params[:ends_at]) || (attrs[:starts_at] + 30.minutes)
    end

    if note.update(attrs)
      expire_calendar_caches!
      redirect_back fallback_location: appointments_path, notice: "Reminder updated", status: :see_other
    else
      redirect_back fallback_location: appointments_path,
        alert: note.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    note = CalendarNote.find(params[:id])
    note.destroy
    expire_calendar_caches!
    redirect_back fallback_location: appointments_path, notice: "Reminder removed", status: :see_other
  end

  private

  def note_params
    params.require(:calendar_note).permit(:note, :starts_at, :ends_at, :done)
  end

  def parse_time(value)
    return nil if value.blank?
    string = value.to_s
    if string.match?(/[zZ]\z|[+-]\d{2}:\d{2}\z/)
      Time.iso8601(string).in_time_zone(Time.zone)
    else
      Time.zone.parse(string)
    end
  rescue ArgumentError, TypeError
    nil
  end

  def expire_calendar_caches!
    expire_dev_page_cache("appointments/index")
    expire_dev_page_cache("appointments/calendar")
    expire_dev_page_cache("dashboard")
  end
end
