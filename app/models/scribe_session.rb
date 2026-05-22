# An AI chair-side scribe session. Audio is transcribed LOCALLY (Whisper, POPIA-safe — never leaves
# the practice PC); the transcript is drafted into a proposed course of treatment + estimate that
# Dr Chalita REVIEWS and confirms. The scribe NEVER auto-charts or auto-bills. (Ivory, Phase 6.)
class ScribeSession < ApplicationRecord
  STATUSES = %w[recording transcribing drafted reviewed discarded].freeze

  belongs_to :patient
  belongs_to :appointment, optional: true
  belongs_to :course_of_treatment, optional: true
  belongs_to :estimate, optional: true

  validates :status, inclusion: { in: STATUSES }

  # Drive "is the patient in the chair?" off the appointment state — only listen while in_chair.
  def self.start_for(appointment)
    create!(patient_id: appointment.patient_id, appointment_id: appointment.id,
            status: "recording", started_at: Time.current)
  end

  # Turn the transcript into a reviewable draft (proposed COT + draft estimate). Never auto-bills.
  def draft_from_transcript!(transcript_text)
    update!(transcript: transcript_text, status: "transcribing", ended_at: Time.current)
    findings = ScribeDraftService.new(transcript_text).extract
    update!(draft: { findings: findings }, status: "drafted")
    findings
  end

  # Build a PROPOSED course of treatment + draft estimate for the dentist to review/accept.
  def build_proposal!
    findings = draft["findings"] || []
    return if findings.empty?
    transaction do
      cot = CourseOfTreatment.create!(patient_id: patient_id, setting: "in_chair",
        status: "planned", description: "AI-drafted plan (review)", notes: "Drafted by chair-side scribe")
      findings.each do |f|
        pc = ProcedureCode.find_by(code: f["code"])
        next unless pc
        cot.treatment_items.create!(procedure_code: pc, tooth_number: f["tooth"], status: "planned")
      end
      est = Estimate.from_course(cot); est.save!
      update!(course_of_treatment: cot, estimate: est, status: "drafted")
      est
    end
  end
end
