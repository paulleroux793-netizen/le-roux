# Ingests the SIDEXIS export into imaging_studies.
# SAFE matching: links to a patient only on a confident name match; everything else is queued as
# `needs_match` for manual linking — NEVER a fuzzy auto-attach (UNCERTAINTIES #8/#20).
#
# Two ingest paths:
#   * #call               — reads db/seed_data/sidexis_manifest.csv (the on-prem bridge manifest).
#   * .scan_sidexis_folder — walks the REAL "5. Sidexis 4 Scans" export folder directly. Each
#     subfolder is one patient (named "FIRSTNAME SURNAME" or an account code). SIDEXIS encodes
#     "SURNAME_FIRSTNAME[_MIDDLE]_<descriptor>_<DATE>_<time>.ext" in every file, so we read the
#     name + date + modality straight off the filename, group images into one study per
#     (capture-date, modality), and file each study under the matched patient. Read-only — the
#     export folder is never written to.
require "csv"

class ImagingImportService
  MANIFEST = Rails.root.join("db", "seed_data", "sidexis_manifest.csv")

  # Default location of the live SIDEXIS export, inside the read-only Elixir mount.
  SIDEXIS_DEFAULT_ROOT = ENV.fetch(
    "SIDEXIS_DATA_ROOT",
    File.join(ENV.fetch("ELIXIR_DATA_ROOT", "/elixir_data"), "5. Sidexis 4 Scans")
  ).freeze

  VIEWABLE_EXTS = %w[.jpg .jpeg .png .tif .tiff .dcm .pdf].freeze

  Result = Struct.new(:total, :created, :matched, :needs_match, :skipped, keyword_init: true)

  # Walk the real SIDEXIS export folder and ingest one study per (patient-folder, date, modality).
  def self.scan_sidexis_folder(root: SIDEXIS_DEFAULT_ROOT, dry_run: false)
    r = Result.new(total: 0, created: 0, matched: 0, needs_match: 0, skipped: 0)
    return r unless Dir.exist?(root)

    Dir.children(root).sort.each do |entry|
      folder_path = File.join(root, entry)
      next unless File.directory?(folder_path)

      # Collect viewable images; skip raw CT slice dumps (DICOMRM/) — a CBCT is one study,
      # not the thousands of numbered raw slices underneath it.
      files = Dir.glob(File.join(folder_path, "**", "*"))
                 .reject { |f| f =~ %r{[\\/]DICOMRM[\\/]}i }
                 .select { |f| File.file?(f) && VIEWABLE_EXTS.include?(File.extname(f).downcase) }
      next if files.empty?

      # Group images into studies keyed by capture-date + modality.
      groups = Hash.new { |h, k| h[k] = { count: 0, sample: nil, name: nil } }
      files.each do |f|
        meta = parse_sidexis_filename(File.basename(f))
        key  = [meta[:date], meta[:modality]]
        g = groups[key]
        g[:count] += 1
        g[:sample] ||= f
        g[:name]   ||= meta[:name]
      end

      groups.each do |(date, modality), g|
        r.total += 1
        source_file_key = "#{modality}__#{date || 'undated'}"
        if ImagingStudy.exists?(source_folder: entry, source_file: source_file_key)
          r.skipped += 1
          next
        end

        patient = match_patient_for(folder: entry, parsed_name: g[:name], date: date)
        status  = patient ? "matched" : "needs_match"
        patient ? (r.matched += 1) : (r.needs_match += 1)
        r.created += 1
        next if dry_run

        ImagingStudy.create!(
          patient: patient,
          modality: modality,
          captured_at: date,
          sidexis_patient_name: display_name_for(entry, g[:name]),
          source_folder: entry,
          source_file: source_file_key,
          status: status,
          notes: "#{g[:count]} image#{g[:count] == 1 ? '' : 's'} from SIDEXIS",
          storage_key: relative_key(g[:sample], root)
        )
      end
    end
    r
  end

  # Parse "SURNAME_FIRSTNAME[_MIDDLE]_<descriptor>_<DATE>_<time>.ext" → { name:, date:, modality: }.
  def self.parse_sidexis_filename(basename)
    stem = basename.sub(/\.[^.]+\z/, "").sub(/\(\d+\)\z/, "")

    # Date: SIDEXIS uses YYYY-MM-DD or YYYYMMDD.
    date = nil
    if (m = stem.match(/(\d{4})-(\d{2})-(\d{2})/))
      date = (Date.new(m[1].to_i, m[2].to_i, m[3].to_i) rescue nil)
    elsif (m = stem.match(/(?<!\d)(\d{4})(\d{2})(\d{2})(?!\d)/))
      date = (Date.new(m[1].to_i, m[2].to_i, m[3].to_i) rescue nil)
    end

    { name: name_from_stem(stem), date: date, modality: modality_from(stem) }
  end

  # SURNAME_FIRSTNAME(_MIDDLE) — the leading UPPERCASE-ish tokens before the descriptor.
  def self.name_from_stem(stem)
    tokens = stem.split("_")
    name_tokens = []
    tokens.each do |tok|
      break unless tok.match?(/\A[A-Za-z][A-Za-z'\-]+\z/) && tok !~ /\A(intraoral|panorama|panoramic|opg|ceph|cephalometric|3d|cbct|axial|longitudinal|photo|light|box|p\d+|vo\d+)\z/i
      name_tokens << tok
    end
    name_tokens = tokens.first(2) if name_tokens.empty?
    # Stored as SURNAME_FIRSTNAME in SIDEXIS → present as "FIRSTNAME SURNAME".
    surname, *rest = name_tokens
    rest.any? ? "#{rest.join(' ')} #{surname}" : surname.to_s
  end

  def self.modality_from(stem)
    case stem
    when /ceph/i                                   then "cephalometric"
    when /3d|cbct|axial|cross.?section|longitudinal|\bvo\d/i then "cbct_3d"
    when /panoram|opg/i                            then "panoramic"
    when /intraoral|bitewing|periapical|\bp\d+\b/i then "intraoral_2d"
    when /light.?box|photo|portrait|clinical/i     then "photo"
    else "other"
    end
  end

  def self.display_name_for(folder, parsed_name)
    return parsed_name if folder.match?(/\A[A-Z]\d{3,}\z/i) && parsed_name.present?
    folder
  end

  # Confident match only: account-code folder, exact normalised name (folder or parsed), or a
  # same-date appointment whose patient surname matches. Anything less stays `needs_match`.
  def self.match_patient_for(folder:, parsed_name:, date:)
    if folder.match?(/\A[A-Z]\d{3,}\z/i)
      acc = BillingAccount.find_by("UPPER(account_code) = ?", folder.upcase)
      return acc.patients.first if acc&.patients&.any?
    end

    [folder, parsed_name].compact.each do |candidate|
      norm = normalize(candidate)
      next if norm.empty?
      hit = Patient.all.detect { |p| normalize(p.full_name) == norm }
      return hit if hit
    end

    # Date cross-reference: a patient seen on the capture date whose surname matches.
    if date && parsed_name.present?
      surname = parsed_name.split(" ").last.to_s
      unless surname.empty?
        appt = Appointment.joins(:patient)
                          .where(start_time: date.beginning_of_day..date.end_of_day)
                          .where("LOWER(patients.last_name) = LOWER(?)", surname)
                          .first
        return appt.patient if appt
      end
    end
    nil
  end

  def self.normalize(s) = s.to_s.downcase.gsub(/[^a-z]/, "")

  # Path relative to the SIDEXIS root — the deep-link the on-prem viewer / file browser uses.
  def self.relative_key(path, root)
    return nil if path.nil?
    rel = path.to_s.sub(/\A#{Regexp.escape(root.to_s)}[\\\/]?/, "")
    File.join("5. Sidexis 4 Scans", rel)
  end

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
