# AI chair-side scribe sessions — list + draft review. Additive route. (Ivory, Phase 6.)
class ScribeSessionsController < ApplicationController
  def index
    sessions = ScribeSession.includes(:patient, :estimate).order(created_at: :desc).limit(100).to_a
    render inertia: "ScribeSessions", props: {
      sessions: sessions.map { |s| session_props(s) },
      stats: { total: ScribeSession.count, drafted: ScribeSession.where(status: "drafted").count }
    }
  end

  def show
    s = ScribeSession.includes(:patient, estimate: :estimate_lines).find(params[:id])
    render inertia: "ScribeSessionShow", props: {
      session: session_props(s).merge(
        transcript: s.transcript,
        findings: (s.draft["findings"] || []),
        estimate: s.estimate && {
          number: s.estimate.estimate_number, total: s.estimate.total,
          lines: s.estimate.estimate_lines.map { |l| { code: l.code, description: l.description, tooth: l.tooth_number, fee: l.unit_fee_cents / 100.0 } }
        }
      )
    }
  end

  private

  def session_props(s)
    {
      id: s.id, patient_name: s.patient.full_name, status: s.status,
      started_at: s.started_at&.iso8601,
      finding_count: (s.draft["findings"] || []).size,
      estimate_number: s.estimate&.estimate_number
    }
  end
end
