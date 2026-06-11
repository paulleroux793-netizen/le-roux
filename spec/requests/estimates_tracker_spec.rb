require 'rails_helper'

# Locks the Estimates Tracker lifecycle colours (EstimatesController#index, Paul's headline
# feature): GREEN = accepted OR the linked course-of-treatment's items are all completed;
# BLUE = not done but the patient has a future (non-cancelled) appointment; YELLOW = outstanding.
RSpec.describe 'Estimates tracker status colours', type: :request do
  let(:patient) { create(:patient) }

  def draft_estimate
    Estimate.create!(patient: patient, status: 'draft', subtotal_cents: 0, vat_cents: 0, total_cents: 1_000)
  end

  # Pull the rendered Inertia props (status_colour per estimate) out of the data-page attribute.
  def colour_of(estimate)
    get '/estimates'
    raw = response.body[/data-page="([^"]*)"/, 1]
    rows = JSON.parse(CGI.unescapeHTML(raw)).dig('props', 'estimates')
    rows.find { |r| r['id'] == estimate.id }&.fetch('status_colour')
  end

  it 'is GREEN when the estimate is accepted' do
    e = Estimate.create!(patient: patient, status: 'accepted', subtotal_cents: 0, vat_cents: 0, total_cents: 1_000)
    expect(colour_of(e)).to eq('green')
  end

  it 'is BLUE when not accepted but the patient has a future appointment' do
    e = draft_estimate
    create(:appointment, patient: patient, start_time: 3.days.from_now)
    expect(colour_of(e)).to eq('blue')
  end

  it 'is YELLOW when not accepted and nothing is booked' do
    e = draft_estimate
    expect(colour_of(e)).to eq('yellow')
  end

  it 'is GREEN when the linked course of treatment is fully completed' do
    cot = CourseOfTreatment.create!(patient: patient, setting: 'in_chair', status: 'planned')
    pc  = ProcedureCode.create!(code: "T#{rand(1_000_000)}", description: 'Done item',
                                vat_treatment: 'zero_rated', default_fee_cents: 1_000)
    TreatmentItem.create!(course_of_treatment: cot, procedure_code: pc, status: 'completed', tooth_number: '11')
    e = Estimate.create!(patient: patient, course_of_treatment: cot, status: 'draft',
                         subtotal_cents: 0, vat_cents: 0, total_cents: 1_000)
    expect(colour_of(e)).to eq('green')
  end

  it 'flags an outstanding estimate older than 30 days as aged (the chase-list)' do
    recent = draft_estimate
    old = Estimate.create!(patient: patient, status: 'draft', subtotal_cents: 0, vat_cents: 0,
                           total_cents: 1_000, created_at: 45.days.ago)
    get '/estimates'
    rows = JSON.parse(CGI.unescapeHTML(response.body[/data-page="([^"]*)"/, 1])).dig('props', 'estimates')
    expect(rows.find { |r| r['id'] == old.id }['aged']).to eq(true)
    expect(rows.find { |r| r['id'] == recent.id }['aged']).to eq(false)
  end
end
