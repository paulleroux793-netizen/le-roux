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
end
