# Shared helper: seed the three real intake templates (from db/seeds/intake_forms.rb)
# and create the pending submissions for a patient, the way IntakeDispatch would.
module IntakeFormsHelper
  def seed_intake_templates!
    load Rails.root.join("db/seeds/intake_forms.rb")
    FormTemplate.active.where(key: IntakeProcessor::KEYS).index_by(&:key)
  end

  def create_pending_intake!(patient)
    seed_intake_templates!.values.map do |template|
      patient.form_submissions.create!(form_template: template).tap(&:mark_sent!)
    end
  end

  def intake_token_for(patient)
    patient.signed_id(purpose: :intake, expires_in: 14.days)
  end
end

RSpec.configure { |c| c.include IntakeFormsHelper }
