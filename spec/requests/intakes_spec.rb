require "rails_helper"

# The public, tokenised patient intake wizard. These routes are UNAUTHENTICATED
# (IntakesController < PublicController) and gated only by the signed token.
RSpec.describe "Intakes", type: :request do
  let(:patient) { create(:patient, first_name: "Thandi", last_name: "Mokoena", phone: "+27821110000") }

  describe "GET /intake/:token" do
    it "renders the wizard for a valid token and marks pending forms opened" do
      submissions = create_pending_intake!(patient)
      get intake_path(token: intake_token_for(patient))

      expect(response).to have_http_status(:ok)
      expect(submissions.map { |s| s.reload.status }).to all(eq("opened"))
    end

    it "renders the invalid state for a bogus token (no leak, still 200)" do
      get intake_path(token: "not-a-real-token")
      expect(response).to have_http_status(:ok)
    end

    it "renders the invalid state for an expired token" do
      create_pending_intake!(patient)
      token = patient.signed_id(purpose: :intake, expires_in: 14.days)

      travel 15.days do
        get intake_path(token: token)
        expect(response).to have_http_status(:ok)
      end
    end

    it "does not require dashboard auth" do
      create_pending_intake!(patient)
      # Even with basic-auth enabled, the public route must stay reachable.
      allow(ENV).to receive(:[]).and_call_original
      get intake_path(token: intake_token_for(patient))
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /intake/:token" do
    let!(:submissions) { create_pending_intake!(patient) }
    let(:answers) do
      {
        patient_details: {
          first_name: "Thandiwe", last_name: "Mokoena", id_number: "9001011234088",
          contact_number: "+27821110000", emergency_contact_name: "Sipho",
          emergency_contact_phone: "+27829990000", has_medical_aid: true,
          scheme_name: "Discovery", member_number: "MM123"
        },
        health_questionnaire: { diabetes: true, allergies_flag: true, allergies: "Penicillin" },
        consent_treatment: { acknowledged: true }
      }
    end

    it "files each form, syncs the patient, and redirects" do
      expect {
        patch intake_path(token: intake_token_for(patient)), params: { answers: answers }
      }.to change { patient.documents.count }.by(3)

      expect(response).to have_http_status(:see_other)
      expect(submissions.map { |s| s.reload.status }).to all(eq("completed"))

      patient.reload
      expect(patient.first_name).to eq("Thandiwe")
      expect(patient.id_number).to eq("9001011234088")
      expect(patient.medical_history.allergies).to eq("Penicillin")
      expect(patient.medical_history.chronic_conditions).to include("Diabetes")
      expect(patient.medical_history.emergency_contact_name).to eq("Sipho")
    end

    it "encrypts the SA ID number at rest (ciphertext in the raw column)" do
      patch intake_path(token: intake_token_for(patient)), params: { answers: answers }

      raw = Patient.connection.select_value(
        Patient.sanitize_sql_array(["SELECT id_number FROM patients WHERE id = ?", patient.id])
      )
      expect(raw).not_to include("9001011234088")
    end

    it "stores the full answer set as encrypted form data" do
      patch intake_path(token: intake_token_for(patient)), params: { answers: answers }

      sub = patient.form_submissions.joins(:form_template)
                   .find_by(form_templates: { key: "health_questionnaire" })
      expect(sub.data["allergies"]).to eq("Penicillin")

      raw = FormSubmission.connection.select_value(
        FormSubmission.sanitize_sql_array(["SELECT data FROM form_submissions WHERE id = ?", sub.id])
      )
      expect(raw).not_to include("Penicillin")
    end

    it "renders the completed state when re-opened after submission" do
      patch intake_path(token: intake_token_for(patient)), params: { answers: answers }
      get intake_path(token: intake_token_for(patient))
      expect(response).to have_http_status(:ok)
    end
  end
end
