require "rails_helper"

RSpec.describe IntakeProcessor do
  let(:patient) { create(:patient, first_name: "Old", last_name: "Name", phone: "+27821110000") }
  before { create_pending_intake!(patient) }

  let(:answers) do
    {
      "patient_details" => {
        "first_name" => "New", "last_name" => "Name", "id_number" => "8505057654083",
        "emergency_contact_name" => "Lerato", "emergency_contact_phone" => "+27829990000",
        "scheme_name" => "Bonitas", "member_number" => "B-99"
      },
      "health_questionnaire" => {
        "diabetes" => true, "epilepsy" => true, "med_anticoagulants" => true,
        "allergies_flag" => true, "allergies" => "Latex"
      },
      "consent_treatment" => { "acknowledged" => true }
    }
  end

  it "completes every intake submission and files a Document for each" do
    expect { described_class.new(patient, answers).save! }
      .to change { patient.documents.count }.by(3)

    statuses = patient.form_submissions.pluck(:status).uniq
    expect(statuses).to eq(["completed"])
  end

  it "syncs the typed details onto the patient (present values only)" do
    described_class.new(patient, answers).save!
    patient.reload
    expect(patient.first_name).to eq("New")
    expect(patient.id_number).to eq("8505057654083")
  end

  it "rolls the questionnaire into the medical history summary fields" do
    described_class.new(patient, answers).save!
    history = patient.reload.medical_history

    expect(history.allergies).to eq("Latex")
    expect(history.chronic_conditions).to include("Diabetes", "Epilepsy")
    expect(history.current_medications).to include("Blood thinners")
    expect(history.emergency_contact_name).to eq("Lerato")
    expect(history.insurance_provider).to eq("Bonitas")
    expect(history.insurance_policy_number).to eq("B-99")
  end

  it "never blanks an existing value with an empty answer" do
    patient.update!(phone: "+27821110000")
    described_class.new(patient, answers.merge("patient_details" => answers["patient_details"].merge("contact_number" => ""))).save!
    expect(patient.reload.phone).to eq("+27821110000")
  end

  it "is idempotent — re-running does not duplicate documents" do
    described_class.new(patient, answers).save!
    expect { described_class.new(patient, answers).save! }
      .not_to change { patient.documents.count }
  end

  it "emails the completed pack to the practice" do
    expect { described_class.new(patient, answers).save! }
      .to have_enqueued_mail(IntakeMailer, :completed)
  end

  it "does not re-email when re-run with nothing new to complete" do
    described_class.new(patient, answers).save!
    expect { described_class.new(patient, answers).save! }
      .not_to have_enqueued_mail(IntakeMailer, :completed)
  end
end
