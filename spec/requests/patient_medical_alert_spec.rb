require 'rails_helper'

# Locks the patient medical-alert data flow (C24): PatientsController#show must ship
# allergies / chronic_conditions / current_medications so the persistent alert banner can render.
# Clinical safety — the dentist relies on this before treatment.
RSpec.describe 'Patient medical-alert data', type: :request do
  it 'ships allergies, conditions and medications in the patient page props' do
    patient = create(:patient)
    PatientMedicalHistory.create!(patient: patient, allergies: 'Penicillin',
                                  chronic_conditions: 'Diabetes', current_medications: 'Metformin')

    get "/patients/#{patient.id}"
    mh = JSON.parse(CGI.unescapeHTML(response.body[/data-page="([^"]*)"/, 1])).dig('props', 'medical_history')
    expect(mh.values_at('allergies', 'chronic_conditions', 'current_medications')).to eq(%w[Penicillin Diabetes Metformin])
  end
end
