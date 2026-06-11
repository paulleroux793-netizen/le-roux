# SIDEXIS imaging studies — review queue + matched studies. Additive route. (Ivory, Phase 5.)
class ImagingController < ApplicationController
  def index
    studies = ImagingStudy.includes(:patient).order(captured_at: :desc).limit(400).to_a
    render inertia: "Imaging", props: {
      studies: studies.map { |s|
        {
          id: s.id, modality: s.modality, modality_label: s.modality_label,
          patient_name: s.patient&.full_name || s.sidexis_patient_name,
          status: s.status, captured_at: s.captured_at&.iso8601, file_name: s.source_file
        }
      },
      stats: {
        total: ImagingStudy.count,
        matched: ImagingStudy.matched.count,
        needs_match: ImagingStudy.needs_match.count,
        by_modality: ImagingStudy.group(:modality).count
      }
    }
  end

  # POST /imaging/scan — kick off a SIDEXIS folder scan in the BACKGROUND.
  # Enqueues PracticeDataSyncJob (async); newly-matched studies appear on the
  # next load. Same job the hourly recurring schedule runs.
  def scan
    PracticeDataSyncJob.perform_later(sources: ["sidexis"])
    redirect_to imaging_path,
                notice: "SIDEXIS sync started in the background — studies will appear shortly."
  rescue StandardError => e
    redirect_to imaging_path, alert: "Could not start sync: #{e.class}: #{e.message}"
  end

  # Stream a study's image from the read-only SIDEXIS archive mounted at /sidexis_archive.
  # Default serves the small .preview.jpg (thumbnail); ?full=1 serves the full .snapshot.png.
  # Binaries never live in Postgres — only the storage_key path does (reference + stream).
  ARCHIVE_ROOT = File.expand_path(ENV.fetch("SIDEXIS_ARCHIVE_ROOT", "/sidexis_archive")).freeze

  def image
    study = ImagingStudy.find(params[:id])
    key = study.storage_key.to_s
    return head(:not_found) if key.blank?
    key = key.sub(/\.preview\.jpg\z/i, ".snapshot.png") if params[:full].present?
    path = File.expand_path(File.join(ARCHIVE_ROOT, key))
    # Path-traversal guard: the resolved path MUST stay inside the archive root.
    return head(:not_found) unless path.start_with?(ARCHIVE_ROOT + File::SEPARATOR) && File.file?(path)
    type = case File.extname(path).downcase
           when ".png" then "image/png"
           when ".jpg", ".jpeg" then "image/jpeg"
           when ".dcm" then "application/dicom"
           else "application/octet-stream"
           end
    response.headers["Cache-Control"] = "private, max-age=86400"
    send_file path, type: type, disposition: "inline"
  end

  # Render the study's RAW DICOM to a PNG with adjustable window/level (brightness/contrast)
  # + invert, via the host render service. This is the diagnostic viewer (vs the low-res preview).
  # Params: wc (window centre), ww (window width), invert. Falls back gracefully if no .dcm.
  def dicom
    study = ImagingStudy.find(params[:id])
    key = study.storage_key.to_s
    return head(:not_found) if key.blank?
    dcm = key.sub(/\.preview\.jpg\z/i, ".dcm")
    path = File.expand_path(File.join(ARCHIVE_ROOT, dcm))
    return head(:not_found) unless path.start_with?(ARCHIVE_ROOT + File::SEPARATOR) && File.file?(path)

    require "net/http"
    q = { path: dcm }
    q[:wc] = params[:wc] if params[:wc].present?
    q[:ww] = params[:ww] if params[:ww].present?
    q[:invert] = "1" if params[:invert].present?
    uri = URI("http://host.docker.internal:8810/render")
    uri.query = URI.encode_www_form(q)
    begin
      res = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 30) { |h| h.get(uri.request_uri) }
    rescue StandardError
      return head(:bad_gateway)
    end
    return head(:not_found) unless res.is_a?(Net::HTTPSuccess)
    response.headers["X-Window-Center"] = res["X-Window-Center"].to_s
    response.headers["X-Window-Width"]  = res["X-Window-Width"].to_s
    response.headers["Cache-Control"] = "private, max-age=3600"
    send_data res.body, type: "image/png", disposition: "inline"
  end
end
