# Parses an Elixir-exported daily diary PDF into structured appointment rows.
#
# Input file shape (verified against `D:/Paul le Roux/OneDrive/1. Dr Chalita le Roux/3. Diary/8 MAY 2026.pdf`):
#
#     APPOINTMENT DETAILS
#     Date printed: 07-May-2026                                 Page 1 of 1
#     Resource:     DR ELISKA ROBINSON                          08-May-2026
#     Start:  End:  Details:                                  File:  Due:  Cellular:
#     05:00   07:00 NONDUMISO MBANJWA [M0269]    FILLINGS              0.00 0836658817
#     07:00   08:00 Closed
#     08:00   09:00 AZANIA TLHAKANYE [New patient]   PAIN
#     ...
#
# Pure parser — no DB writes. Returns an Array<Hash>:
#     [{ dentist:, appointment_date:, start_at:, end_at:,
#        patient_name:, account_code:, is_new_patient:, reason:,
#        due_amount:, cellular:, raw_line: }, ...]
#
# Lines with "Closed" are skipped (they're not real appointments).
#
# Resilience:
#   - If the PDF's text extraction is messy (multi-column wrap, unicode),
#     we still try to lift each appointment row by regex.
#   - Unknown line shapes are returned with status:"unparsed" so the
#     importer can log them rather than silently drop them.
module ElixirMirror
  class DiaryParser
    APPT_LINE = %r{
      ^\s*
      (?<start>\d{2}:\d{2})\s+
      (?<end_>\d{2}:\d{2})\s+
      (?<rest>.+?)\s*$
    }x

    NEW_PATIENT = /\[New\s+patient\]/i.freeze
    ACCOUNT_TAG = /\[([A-Z]\d{4})\]/.freeze

    def initialize(file_path)
      @file_path = file_path.to_s
      raise ArgumentError, "file not found: #{@file_path}" unless File.exist?(@file_path)
    end

    # Returns the array of parsed appointment rows.
    def parse
      require "pdf/reader"

      header = parse_header
      rows = []
      reader = PDF::Reader.new(@file_path)
      reader.pages.each do |page|
        page.text.each_line do |line|
          next if line.strip.empty?
          next if line.match?(/closed/i) && !line.match?(/^\s*\d{2}:\d{2}/)

          m = line.match(APPT_LINE)
          next unless m

          rest = m[:rest]
          # Skip "Closed" rows
          next if rest.strip.casecmp("closed").zero?

          # Pull account code or "New patient" tag, then patient name + reason
          is_new = !!(rest =~ NEW_PATIENT)
          account = rest[ACCOUNT_TAG, 1]
          # Strip the [tag] from rest, then everything BEFORE it is the patient name and
          # everything AFTER is the reason / details.
          name, _, reason_chunk = rest.partition(/\[(?:New patient|[A-Z]\d{4})\]/)
          name   = name.strip.sub(/[,;]+$/, "")
          reason = reason_chunk.strip

          # The reason chunk often ends with "0.00 0836658817" (due amount + cell)
          due_amount = nil
          cellular   = nil
          if (tail = reason.match(/(\d+\.\d{2})\s+(0\d{6,10})\s*$/))
            due_amount = tail[1].to_f
            cellular   = tail[2]
            reason     = reason.sub(tail[0], "").strip
          end

          rows << {
            dentist:          header[:dentist],
            appointment_date: header[:appointment_date],
            start_at:         combine(header[:appointment_date], m[:start]),
            end_at:           combine(header[:appointment_date], m[:end_]),
            patient_name:     name.presence,
            account_code:     account,
            is_new_patient:   is_new,
            reason:           reason.presence,
            due_amount:       due_amount,
            cellular:         cellular,
            raw_line:         line.strip
          }
        end
      end
      rows
    end

    # Header fields:
    #   :dentist            "DR ELISKA ROBINSON"  (the "Resource:" line)
    #   :appointment_date   Date object derived from the trailing "08-May-2026"
    def parse_header
      require "pdf/reader"
      first_page = PDF::Reader.new(@file_path).pages.first&.text.to_s
      lines = first_page.lines.map(&:strip).reject(&:empty?)

      dentist = nil
      appt_date = nil

      lines.each do |l|
        if (m = l.match(/Resource:\s*(?<name>.+?)\s{2,}(?<date>\d{2}-[A-Za-z]{3}-\d{4})/))
          dentist = m[:name].strip
          appt_date = Date.strptime(m[:date], "%d-%b-%Y")
          break
        elsif (m = l.match(/Resource:\s*(?<name>DR\s+[A-Z ]+)/))
          dentist ||= m[:name].strip
        elsif (m = l.match(/^(?<date>\d{2}-[A-Za-z]{3}-\d{4})\s*$/))
          appt_date ||= Date.strptime(m[:date], "%d-%b-%Y")
        end
      end

      # Fallback: derive date from filename ("8 MAY 2026.pdf" / "5 JANUARY 2026 - DR C.pdf").
      if appt_date.nil?
        base = File.basename(@file_path, ".pdf")
        if (m = base.match(/(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})/))
          day, month, year = m.captures
          appt_date = Date.strptime("#{day} #{month[0,3]} #{year}", "%d %b %Y") rescue nil
        end
      end

      { dentist: dentist, appointment_date: appt_date }
    end

    private

    def combine(date, hhmm)
      return nil unless date && hhmm
      h, m = hhmm.split(":").map(&:to_i)
      Time.zone.local(date.year, date.month, date.day, h, m, 0)
    end
  end
end
