# Recalls — preventive 6-month check-up follow-ups. Additive route. (Ivory, Phase 5.)
class RecallsController < ApplicationController
  def index
    recalls = Recall.includes(:patient).order(:due_on).limit(300).to_a
    render inertia: "Recalls", props: {
      recalls: recalls.map { |r|
        { id: r.id, patient_name: r.patient.full_name, recall_type: r.recall_type,
          due_on: r.due_on.iso8601, status: r.status, overdue: r.due_on < Date.current }
      },
      stats: { total: Recall.count, due: Recall.where(status: "due").count }
    }
  end
end
