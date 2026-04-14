class SearchController < ApplicationController
  # Phase 9.6 sub-area #5 — Functional Global Search.
  #
  # Returns grouped JSON results for the navbar search dropdown:
  #   { query: "...", patients: [...], appointments: [...], conversations: [...] }
  #
  # Deliberately JSON (not Inertia) so the dropdown can fetch results
  # inline without a full page re-render. Each group is capped at
  # RESULT_LIMIT so the dropdown stays compact and the query stays
  # fast even on a freshly-seeded dev db.
  RESULT_LIMIT = 5

  # Ignore noise queries — a single character matches too much to
  # be useful and wastes a DB round-trip on every keystroke.
  MIN_QUERY_LENGTH = 2

  def index
    q = params[:q].to_s.strip

    if q.length < MIN_QUERY_LENGTH
      return render json: empty_payload(q)
    end

    render json: {
      query: q,
      patients:      search_patients(q),
      appointments:  search_appointments(q),
      conversations: search_conversations(q)
    }
  end

  private

  def empty_payload(q)
    { query: q, patients: [], appointments: [], conversations: [] }
  end

  # Patients — match against name, phone, email. ILIKE keeps the
  # query portable across Postgres deployments without needing
  # pg_trgm for a small (~500 row) patient table.
  def search_patients(q)
    pattern = "%#{sanitize_like(q)}%"
    Patient
      .where(
        "first_name ILIKE :p OR last_name ILIKE :p OR " \
        "(first_name || ' ' || last_name) ILIKE :p OR " \
        "phone ILIKE :p OR email ILIKE :p",
        p: pattern
      )
      .order(:last_name, :first_name)
      .limit(RESULT_LIMIT)
      .map { |p|
        {
          id: p.id,
          full_name: p.full_name,
          phone: p.phone,
          email: p.email,
          url: "/patients/#{p.id}"
        }
      }
  end

  # Appointments — match by patient name or reason. Joined query so
  # we can search across both tables in a single round-trip.
  def search_appointments(q)
    pattern = "%#{sanitize_like(q)}%"
    Appointment
      .joins(:patient)
      .where(
        "patients.first_name ILIKE :p OR patients.last_name ILIKE :p OR " \
        "(patients.first_name || ' ' || patients.last_name) ILIKE :p OR " \
        "appointments.reason ILIKE :p",
        p: pattern
      )
      .order(start_time: :desc)
      .limit(RESULT_LIMIT)
      .map { |a|
        {
          id: a.id,
          patient_name: a.patient.full_name,
          start_time: a.start_time.iso8601,
          status: a.status,
          reason: a.reason,
          url: "/appointments/#{a.id}"
        }
      }
  end

  # Conversations — match by patient name. Message bodies are in a
  # jsonb column; searching those well needs a GIN index we haven't
  # added yet, so we scope to the patient join for now and revisit
  # if the team needs content search.
  def search_conversations(q)
    pattern = "%#{sanitize_like(q)}%"
    Conversation
      .joins(:patient)
      .where(
        "patients.first_name ILIKE :p OR patients.last_name ILIKE :p OR " \
        "(patients.first_name || ' ' || patients.last_name) ILIKE :p",
        p: pattern
      )
      .order(updated_at: :desc)
      .limit(RESULT_LIMIT)
      .map { |c|
        {
          id: c.id,
          patient_name: c.patient.full_name,
          channel: c.channel,
          status: c.status,
          updated_at: c.updated_at.iso8601,
          url: "/conversations/#{c.id}"
        }
      }
  end

  # Escape LIKE metacharacters so a user typing "50%" doesn't get
  # a wildcard match. Backslashes are also escaped for the same
  # reason. Parameterised binding handles actual SQL injection.
  def sanitize_like(value)
    value.gsub(/[\\%_]/) { |c| "\\#{c}" }
  end
end
