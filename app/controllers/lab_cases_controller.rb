# Lab-case worklist: the daily "what's out at the lab / what's due back" screen.
# Builds on the existing TreatmentItem lab_* columns and the per-item Send-to-lab /
# Returned controls on the treatment plan (CourseOfTreatmentShow → PATCH
# /treatment_items/:id). This is the dedicated cross-patient worklist that was
# missing — read-only; the page ticks cases back in via the existing PATCH endpoint.
class LabCasesController < ApplicationController
  def index
    out = TreatmentItem.at_lab
                       .includes(:procedure_code, course_of_treatment: :patient)
                       .order(Arel.sql("lab_due_on ASC NULLS LAST"))
                       .to_a
    returned = TreatmentItem.returned_recently
                            .includes(:procedure_code, course_of_treatment: :patient)
                            .order(lab_returned_on: :desc).limit(50).to_a

    render inertia: "Lab", props: {
      out_at_lab: out.map { |i| row(i) },
      returned:   returned.map { |i| row(i) },
      stats: { out: out.size, overdue: out.count(&:lab_overdue?), returned_30d: returned.size }
    }
  end

  private

  def row(item)
    pt = item.course_of_treatment&.patient
    {
      id: item.id,
      patient_id: pt&.id,
      patient_name: pt&.full_name,
      description: item.procedure_code&.description,
      tooth: item.tooth_number,
      lab_name: item.lab_name,
      sent_on: item.lab_sent_on&.iso8601,
      due_on: item.lab_due_on&.iso8601,
      returned_on: item.lab_returned_on&.iso8601,
      overdue: item.lab_overdue?
    }
  end
end
