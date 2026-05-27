# Orchestrates Elixir-mirror imports: takes one file, dispatches to the
# right parser, upserts the resulting rows into the right snapshot table,
# and records the run in elixir_mirror_imports.
#
# Idempotent — re-importing the same file is a no-op (matched by sha256).
# Re-importing an edited version of a previously-imported file will
# UPDATE rows in place (matched by the unique indexes on each snapshot
# table).
#
# Usage:
#   ElixirMirror::Importer.new("/.../3. Diary/8 MAY 2026.pdf").run
#   ElixirMirror::Importer.scan_default_locations   # imports any new files
#
# Default locations (from CLAUDE.md):
#   D:/Paul le Roux/OneDrive/1. Dr Chalita le Roux/3. Diary/*.pdf
#   D:/Paul le Roux/OneDrive/1. Dr Chalita le Roux/4. Transaction report/*.pdf
#   D:/Paul le Roux/OneDrive/1. Dr Chalita le Roux/1. Policies and Procedures/Estimates listing.xlsx
#
# All reads are read-only — Ivory NEVER writes back to that folder
# (the hard constraint per CLAUDE.md and go_live_decisions memory).
require "digest"

module ElixirMirror
  class Importer
    DEFAULT_ELIXIR_ROOT = ENV.fetch(
      "ELIXIR_DATA_ROOT",
      "/d/Paul le Roux/OneDrive/1. Dr Chalita le Roux"
    ).freeze

    def initialize(file_path)
      @file_path = file_path.to_s
      raise ArgumentError, "file not found: #{@file_path}" unless File.exist?(@file_path)
      @kind = detect_kind(@file_path)
      @file_name = File.basename(@file_path)
      @sha256 = Digest::SHA256.file(@file_path).hexdigest
    end

    def run
      # Short-circuit if this exact file already imported successfully.
      existing = ElixirMirrorImport.succeeded.find_by(file_sha256: @sha256, file_kind: @kind)
      if existing
        return existing
      end

      record = ElixirMirrorImport.create!(
        file_path: @file_path, file_name: @file_name, file_kind: @kind,
        file_sha256: @sha256, status: "running", started_at: Time.current
      )

      begin
        parsed_rows = parse_rows
        inserted = 0
        skipped  = 0

        ActiveRecord::Base.transaction do
          parsed_rows.each do |row|
            result = upsert(row)
            case result
            when :inserted then inserted += 1
            when :updated  then inserted += 1
            else                skipped += 1
            end
          end
        end

        record.update!(
          status: "succeeded",
          rows_parsed: parsed_rows.size,
          rows_inserted: inserted,
          rows_skipped: skipped,
          finished_at: Time.current
        )
        record
      rescue StandardError => e
        record.update!(
          status: "failed",
          error_message: "#{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}",
          finished_at: Time.current
        )
        Rails.logger.error("[ElixirMirror::Importer] #{@file_name} failed: #{e.class}: #{e.message}")
        raise
      end
    end

    # Scans the default OneDrive layout and imports any file that hasn't
    # been imported yet. Returns an Array<ElixirMirrorImport>.
    def self.scan_default_locations
      results = []
      diary_glob = Dir.glob(File.join(DEFAULT_ELIXIR_ROOT, "3. Diary", "*.pdf"))
      txn_glob   = Dir.glob(File.join(DEFAULT_ELIXIR_ROOT, "4. Transaction report", "*.pdf"))
      est_glob   = Dir.glob(File.join(DEFAULT_ELIXIR_ROOT, "1. Policies and Procedures", "Estimates listing.xlsx"))

      (diary_glob + txn_glob + est_glob).each do |path|
        begin
          results << new(path).run
        rescue StandardError => e
          Rails.logger.warn("[ElixirMirror::Importer] skipping #{path}: #{e.class}: #{e.message}")
        end
      end
      results
    end

    private

    def detect_kind(path)
      if path =~ %r{[\\/]3\.\s*Diary[\\/]}i || path.downcase.include?("diary")
        "diary"
      elsif path =~ %r{[\\/]4\.\s*Transaction}i || path.downcase.include?("transaction")
        "transaction_report"
      elsif path.downcase.end_with?(".xlsx") && path.downcase.include?("estimates")
        "estimates_listing"
      else
        # Heuristic fallback: PDFs go to whichever folder they live in;
        # XLSXs default to estimates_listing.
        path.downcase.end_with?(".xlsx") ? "estimates_listing" : "diary"
      end
    end

    def parse_rows
      case @kind
      when "diary"               then ElixirMirror::DiaryParser.new(@file_path).parse
      when "transaction_report"  then ElixirMirror::TransactionReportParser.new(@file_path).parse
      when "estimates_listing"   then ElixirMirror::EstimatesListingParser.new(@file_path).parse
      else                            raise ArgumentError, "unknown file kind: #{@kind}"
      end
    end

    def upsert(row)
      case @kind
      when "diary"              then upsert_diary(row)
      when "transaction_report" then upsert_transaction(row)
      when "estimates_listing"  then upsert_estimate(row)
      end
    end

    def upsert_diary(row)
      return :skipped if row[:start_at].nil?
      existing = ElixirDiarySnapshot.find_by(
        source_file: @file_name,
        appointment_start_at: row[:start_at]
      )
      attrs = {
        diary_date:           row[:appointment_date],
        dentist:              row[:dentist],
        appointment_start_at: row[:start_at],
        appointment_end_at:   row[:end_at],
        patient_name:         row[:patient_name],
        account_code:         row[:account_code],
        is_new_patient:       row[:is_new_patient].to_s == "true" || row[:is_new_patient] == true,
        reason:               row[:reason],
        due_amount:           row[:due_amount],
        cellular:             row[:cellular],
        source_file:          @file_name,
        imported_at:          Time.current,
        raw_payload:          row.except(:start_at, :end_at, :appointment_date)
      }
      if existing
        existing.update!(attrs)
        :updated
      else
        ElixirDiarySnapshot.create!(attrs)
        :inserted
      end
    end

    def upsert_transaction(row)
      return :skipped if row[:account_code].blank? || row[:procedure_code].blank?
      key = {
        source_file:      @file_name,
        transaction_date: row[:transaction_date],
        account_code:     row[:account_code],
        procedure_code:   row[:procedure_code],
        tooth:            row[:tooth],
        debit:            row[:debit]
      }
      existing = ElixirTransactionSnapshot.find_by(key)
      attrs = row.except(:raw_line).merge(
        source_file: @file_name,
        imported_at: Time.current,
        raw_payload: { raw_line: row[:raw_line] }
      )
      if existing
        existing.update!(attrs)
        :updated
      else
        ElixirTransactionSnapshot.create!(attrs)
        :inserted
      end
    end

    def upsert_estimate(row)
      return :skipped if row[:patient_name].blank? && row[:account_code].blank?
      existing = ElixirEstimateSnapshot.find_by(source_file: @file_name, row_index: row[:row_index])
      attrs = row.merge(source_file: @file_name, imported_at: Time.current, raw_payload: row)
      if existing
        existing.update!(attrs)
        :updated
      else
        ElixirEstimateSnapshot.create!(attrs)
        :inserted
      end
    end
  end
end
