# Ingests the SIDEXIS export (via a manifest the on-prem bridge produces) into imaging_studies.
# SAFE matching: links to a patient only on a confident name match; everything else is queued as
# `needs_match` for manual linking — NEVER a fuzzy auto-attach (UNCERTAINTIES #8/#20).
# Reads db/seed_data/sidexis_manifest.csv (gitignored — real patient names).
require "csv"

class ImagingImportService
  MANIFEST = Rails.root.join("db", "seed_data", "sidexis_manifest.csv")

  Result = Struct.new(:total, :created, :matched, :needs_match, :skipped, keyword_init: true)

  def initialize(path: MANIFEST)
    @path = path
  end

  def call(dry_run: false)
    r = Result.new(total: 0, created: 0, matched: 0, needs_match: 0, skipped: 0)
    return r unless File.exist?(@path)

    CSV.foreach(@path, headers: true) do |row|
      r.total += 1
      folder = row["patient_folder"].to_s.strip
      file   = row["file_name"].to_s.strip
      next (r.skipped += 1) if folder.empty?

      # Idempotency: skip if this source file is already imported.
      if ImagingStudy.exists?(source_folder: folder, source_file: file)
        r.skipped += 1; next
      end

      patient = match_patient(folder)
      status  = patient ? "matched" : "needs_match"
      r.matched += 1 if patient
      r.needs_match += 1 unless patient
      r.created += 1

      next if dry_run
      ImagingStudy.create!(
        patient: patient, modality: row["modality"].presence || "other",
        captured_at: parse_time(row["captured_at"]), sidexis_patient_name: folder,
        source_folder: folder, source_file: file, status: status
      )
    end
    r
  end

  private

  # Confident match only: exact normalised full-name, or an account code folder (e.g. "B0018").
  def match_patient(folder)
    if folder.match?(/\A[A-Z]\d{3,}\z/i) # looks like an account code
      acc = BillingAccount.find_by("UPPER(account_code) = ?", folder.upcase)
      return acc&.patients&.first
    end
    norm = normalize(folder)
    Patient.all.detect { |p| normalize(p.full_name) == norm }
  end

  def normalize(s) = s.to_s.downcase.gsub(/[^a-z]/, "")

  def parse_time(v)
    return nil if v.blank?
    Time.zone.parse(v)
  rescue ArgumentError
    nil
  end
end
