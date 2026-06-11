require 'rails_helper'

# Covers the lab-case worklist + send/return workflow (TreatmentItem lab_* columns).
RSpec.describe 'Lab cases', type: :request do
  let(:patient) { create(:patient) }
  let(:cot)     { CourseOfTreatment.create!(patient: patient, setting: 'in_chair', status: 'planned') }
  let(:code) do
    ProcedureCode.create!(code: "LAB#{rand(1_000_000)}", description: 'Crown',
                          vat_treatment: 'zero_rated', default_fee_cents: 500_000)
  end

  def item(attrs = {})
    TreatmentItem.create!({ course_of_treatment: cot, procedure_code: code,
                            status: 'completed', tooth_number: '11' }.merge(attrs))
  end

  describe 'GET /lab' do
    it 'renders the Lab worklist page' do
      get '/lab'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Lab')
      expect(response.body).to include('out_at_lab')
      expect(response.body).to include('returned')
    end

    it 'shows a sent-not-returned case as out at the lab' do
      item(lab_name: 'Acme Dental Lab', lab_sent_on: Date.current - 5, lab_due_on: Date.current - 1)
      get '/lab'
      expect(response.body).to include('Acme Dental Lab')
    end

    it 'excludes a returned case from the out-at-lab list' do
      item(lab_name: 'BackAlready Lab', lab_sent_on: Date.current - 10, lab_returned_on: Date.current - 1)
      get '/lab'
      # It still appears in "returned", but is not counted as out at the lab.
      expect(TreatmentItem.at_lab).to be_empty
    end
  end

  # Cases are sent/returned via the existing PATCH /treatment_items/:id (the
  # treatment-plan Send-to-lab / Returned controls). Confirm that path drives the
  # worklist's at_lab state, since the page ticks cases back in through it.
  describe 'PATCH /treatment_items/:id (existing lab controls)' do
    it 'ticks a case back in and drops it from the out-at-lab list' do
      ti = item(lab_name: 'X', lab_sent_on: Date.current - 3, lab_due_on: Date.current)
      expect(TreatmentItem.at_lab).to include(ti)
      patch "/treatment_items/#{ti.id}", params: { lab_returned_on: Date.current.iso8601 }
      ti.reload
      expect(ti.lab_returned_on).to eq(Date.current)
      expect(TreatmentItem.at_lab).not_to include(ti)
    end
  end

  describe 'TreatmentItem lab scopes/predicates' do
    it 'at_lab includes outstanding cases and excludes returned ones' do
      out  = item(lab_sent_on: Date.current - 2)
      back = item(lab_sent_on: Date.current - 10, lab_returned_on: Date.current - 1)
      expect(TreatmentItem.at_lab).to include(out)
      expect(TreatmentItem.at_lab).not_to include(back)
    end

    it 'flags an overdue case' do
      overdue = item(lab_sent_on: Date.current - 5, lab_due_on: Date.current - 1)
      ontime  = item(lab_sent_on: Date.current - 1, lab_due_on: Date.current + 3)
      expect(overdue.lab_overdue?).to be(true)
      expect(ontime.lab_overdue?).to be(false)
    end
  end
end
