# Parses an Elixir Transaction Analysis PDF into structured line rows.
#
# Source file shape (verified against `4. Transaction report/8 MAY 2026.pdf`):
#
#     TARIFF: ALL                DR CHALITA LE ROUX INC
#                                TRANSACTION ANALYSIS
#     DATASET: DR C LE ROUX      ...
#     DATE        DETAILS                       DEPENDANT/RECEIPT    TEETH  ACCOUNT  YOUR CODE  UNITS  PAT.DUE  SCH.DUE  DEBITS  CREDITS
#     PROVIDER:   DR ELISKA ROBINSON
#     08/05/2026  ELS,M MRS    MICHELLE: 10/02/1981          17  E0011    8369         1  R0.00   R0.00  R1,251.66  R0.00
#     ...
#                                                                                        PATIENT TOTAL: R5,244.51
#                                                                                        DAY TOTAL:     R32,991.89  -R32,991.89
#                                                                                        PROVIDER TOTAL:R32,991.89  -R32,991.89
#
# Pure parser. Returns an Array<Hash> of line rows.
#
# Each line maps to one row in elixir_transaction_snapshots:
#   { transaction_date:, dentist:, patient_surname:, dependant_name:,
#     account_code:, procedure_code:, tooth:, units:,
#     pat_due:, sch_due:, debit:, credit:, raw_line: }
#
# The PROVIDER and DAY-TOTAL rows are dropped — only line items survive.
module ElixirMirror
  class TransactionReportParser
    PROVIDER_LINE = /^\s*PROVIDER:\s*(?<provider>.+?)\s*$/i.freeze

    # Line shapes we recognise:
    #   "08/05/2026 ELS,M MRS  MICHELLE: 10/02/1981  17  E0011  8369  1  R0.00  R0.00  R1,251.66  R0.00"
    #   "08/05/2026 ELS,M MRS                          E0011  8109  2  R0.00  R0.00  R136.79     R0.00"
    #   "08/05/2026 ELS,M MRS  N/A                     E0011  P-CARD 1  R0.00  R0.00  R0.00      -R5,244.51"
    #
    # Strategy: anchor on the leading date, the account code (A0000-Z9999),
    # and the four trailing currency cells. Pull tooth + dependant info
    # from what's between.
    DATE_RE     = %r{(\d{2}/\d{2}/\d{4})}.freeze
    ACCOUNT_RE  = /([A-Z]\d{3,4})/.freeze
    CODE_RE     = /([A-Z0-9]{1,5}(?:-CARD|-CASH)?|B\d{2}|C\d{2}|\d{4})/.freeze
    MONEY_RE    = /-?R[\d,]+\.\d{2}/.freeze

    def initialize(file_path)
      @file_path = file_path.to_s
      raise ArgumentError, "file not found: #{@file_path}" unless File.exist?(@file_path)
    end

    # Returns: Array<Hash> of line rows + a :_summary hash with day/provider totals.
    def parse
      require "pdf/reader"

      rows = []
      current_provider = nil

      PDF::Reader.new(@file_path).pages.each do |page|
        page.text.each_line do |line|
          stripped = line.strip
          next if stripped.empty?

          if (m = stripped.match(PROVIDER_LINE))
            current_provider = m[:provider]
            next
          end

          # Skip EDI status sub-lines and totals
          next if stripped.start_with?("EDI Date")
          next if stripped =~ /^(PATIENT|DAY|PROVIDER|SUBTOTAL|TOTAL)\s+(TOTAL|TURNOVER)/i
          next if stripped =~ /^(SUMMARY|DATASET|PROVIDER|CLINIC|TARIFF|MEDICAL|LEDGER|DATE|EXCLUDE|DATE\s+RANGE|DATE\s+OF|\*)/i

          row = parse_line(stripped, current_provider)
          rows << row if row
        end
      end
      rows
    end

    private

    def parse_line(line, dentist)
      # Must start with a DD/MM/YYYY date
      return nil unless (date_match = line.match(/\A(?<date>\d{2}\/\d{2}\/\d{4})\s+(?<rest>.+)/))

      date = Date.strptime(date_match[:date], "%d/%m/%Y") rescue nil
      return nil unless date

      rest = date_match[:rest]

      # Pull the four trailing money cells (PAT.DUE, SCH.DUE, DEBIT, CREDIT)
      monies = rest.scan(MONEY_RE)
      return nil if monies.size < 4

      pat_due, sch_due, debit, credit = monies.last(4).map { |m| money_to_decimal(m) }
      # Strip trailing monies + any final whitespace
      head = rest.sub(/(?:#{MONEY_RE}\s*){4}\z/, "").rstrip

      # Pull units (the integer immediately before the four money cells)
      units = 1
      if (m = head.match(/\s+(\d+)\s*\z/))
        units = m[1].to_i
        head  = head.sub(/\s+\d+\s*\z/, "").rstrip
      end

      # Pull procedure code (the trailing token: 8369 / P-CARD / B01 / C26 etc.)
      code = nil
      if (m = head.match(/\s+([A-Z0-9]{1,6}(?:-CARD|-CASH)?|B\d{2}|C\d{2})\s*\z/))
        code = m[1]
        head = head.sub(/\s+#{Regexp.escape(code)}\s*\z/, "").rstrip
      else
        return nil   # no recognizable code → skip the line
      end

      # Pull the account code (A0000–Z9999)
      account = nil
      if (m = head.match(/\s+([A-Z]\d{3,4})(?!\d)\s*\z/))
        account = m[1]
        head = head.sub(/\s+#{Regexp.escape(account)}\s*\z/, "").rstrip
      else
        return nil   # no account → skip
      end

      # Pull the tooth (an integer 11-48, FDI two-digit notation), if present
      tooth = nil
      if (m = head.match(/\s+(\d{2})\s*\z/))
        candidate = m[1].to_i
        if [11..18, 21..28, 31..38, 41..48, 51..55, 61..65, 71..75, 81..85].any? { |range| range.cover?(candidate) }
          tooth = m[1]
          head = head.sub(/\s+#{Regexp.escape(tooth)}\s*\z/, "").rstrip
        end
      end

      # What remains in `head` is "PATIENT SURNAME, FIRSTINITIAL MR/MRS  DEPENDANT_NAME: DOB"
      # Split on two-or-more spaces (which is how Elixir delimits cells in the PDF).
      patient_surname, dependant_name = head.split(/\s{2,}/, 2)
      patient_surname = patient_surname.to_s.strip
      dependant_name  = dependant_name.to_s.strip.presence

      # Treat "N/A" dependant as the payment-receipt row
      dependant_name = nil if dependant_name == "N/A"

      {
        transaction_date: date,
        dentist:          dentist,
        patient_surname:  patient_surname.presence,
        dependant_name:   dependant_name,
        account_code:     account,
        procedure_code:   code,
        tooth:            tooth,
        units:            units,
        pat_due:          pat_due,
        sch_due:          sch_due,
        debit:            debit,
        credit:           credit.abs,           # store credits as positive magnitudes
        raw_line:         line
      }
    end

    def money_to_decimal(str)
      sign = str.start_with?("-") ? -1 : 1
      n = str.gsub(/[R,\-]/, "")
      sign * BigDecimal(n)
    rescue StandardError
      BigDecimal(0)
    end
  end
end
