# Parses the Estimates listing.xlsx that reception (Shaune) maintains.
#
# Source file shape (verified against
# `1. Policies and Procedures/Estimates listing.xlsx`):
#
#     A: NAME (patient)
#     B: ACCOUNT
#     C: DATE ESTIMATE SENT  (Excel serial date)
#     D: ESTIMATE DETAILS    (free-text procedure list)
#     E: LAST FOLLOW UP      (Excel serial date OR free-text note)
#     F: VALUE OF TREATMENT
#     G: UPDATE NOTE         (long free-text "Shaune sent a WA..." note)
#     H: Dr
#     I: DOES THE PATIENT KNOW WHAT IS THE NEXT TREATMENT WE NEED TO DO?
#     J: LEGEND
#
# Pure parser. Returns an Array<Hash>, one element per data row.
module ElixirMirror
  class EstimatesListingParser
    def initialize(file_path)
      @file_path = file_path.to_s
      raise ArgumentError, "file not found: #{@file_path}" unless File.exist?(@file_path)
    end

    def parse
      require "roo"

      rows = []
      xlsx = Roo::Excelx.new(@file_path)
      sheet = xlsx.sheet(0)

      (2..sheet.last_row).each do |i|
        a = sheet.cell(i, "A")
        b = sheet.cell(i, "B")
        # Skip blank rows (no name AND no account)
        next if a.to_s.strip.empty? && b.to_s.strip.empty?

        rows << {
          patient_name:      string(a),
          account_code:      string(b),
          date_sent:         excel_date(sheet.cell(i, "C")),
          details:           string(sheet.cell(i, "D")),
          last_followup_at:  excel_date(sheet.cell(i, "E")),
          value:             excel_money(sheet.cell(i, "F")),
          update_note:       string(sheet.cell(i, "G")),
          dentist:           string(sheet.cell(i, "H")),
          patient_aware:     string(sheet.cell(i, "I")),
          legend:            string(sheet.cell(i, "J")),
          row_index:         i
        }
      end
      rows
    ensure
      xlsx&.close if xlsx.respond_to?(:close)
    end

    private

    def string(v)
      v.to_s.strip.presence
    end

    # Roo returns Date objects for proper date cells; sometimes the field
    # has a free-text note instead. We accept either.
    def excel_date(v)
      return nil if v.nil?
      return v if v.is_a?(Date)
      return v.to_date if v.respond_to?(:to_date) && !v.is_a?(String)
      # Try parsing free text
      Date.parse(v.to_s) rescue nil
    end

    def excel_money(v)
      return nil if v.nil? || v.to_s.strip.empty?
      return BigDecimal(v.to_s) if v.is_a?(Numeric)
      cleaned = v.to_s.gsub(/[R,\s]/, "")
      BigDecimal(cleaned) rescue nil
    end
  end
end
