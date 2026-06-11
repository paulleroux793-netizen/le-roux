# Recalls — preventive 6-month check-up follow-ups. Additive route. (Ivory, Phase 5.)
class RecallsController < ApplicationController
  def index
    recalls = Recall.includes(:patient).order(:due_on).limit(300).to_a
    render inertia: "Recalls", props: {
      recalls: recalls.map { |r|
        { id: r.id, patient_id: r.patient_id, patient_name: r.patient.full_name,
          patient_phone: r.patient.display_phone, recall_type: r.recall_type,
          due_on: r.due_on.iso8601, status: r.status, overdue: r.due_on < Date.current }
      },
      # Pipeline counts so reception can see the recall funnel at a glance
      # (due → contacted → booked), not just the to-do count.
      stats: {
        total: Recall.count,
        due: Recall.where(status: "due").count,
        contacted: Recall.where(status: "contacted").count,
        booked: Recall.where(status: "booked").count,
        overdue: Recall.where(status: "due").where("due_on < ?", Date.current).count
      }
    }
  end

  # PATCH /recalls/:id — reception works the list: one-tap mark contacted / booked / done.
  def update
    recall = Recall.find(params[:id])
    new_status = params[:status].to_s
    unless Recall::STATUSES.include?(new_status)
      return redirect_to recalls_path, alert: "Invalid status", status: :see_other
    end
    recall.update!(status: new_status)
    AuditService.log(action: "recall.#{new_status}",
                     summary: "Recall for #{recall.patient.full_name} marked #{new_status}",
                     resource: recall, performed_by: audit_performer, ip_address: request.remote_ip)
    redirect_to recalls_path, notice: "Recall marked #{new_status}", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to recalls_path, alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end
end
