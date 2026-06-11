require 'rails_helper'

# Locks the dashboard estimate-pipeline KPI (PagesController#dashboard, C14): the front-desk
# dashboard surfaces the ACTIONABLE pipeline = un-accepted estimates from the last 90 days
# (older imported drafts are historical, not a live follow-up list). Guards the scoping so it
# can't silently regress back to "all drafts ever" (which inflated it to R72m).
RSpec.describe 'Dashboard estimate-pipeline KPI', type: :request do
  let(:patient) { create(:patient) }

  def dashboard_stats
    get '/'
    raw = response.body[/data-page="([^"]*)"/, 1]
    JSON.parse(CGI.unescapeHTML(raw)).dig('props', 'stats')
  end

  it 'counts recent un-accepted estimates and their value, excluding ones older than 90 days' do
    # Recent draft (R50) → counts; old sent (R30, 120 days) → excluded by the 90-day window.
    Estimate.create!(patient: patient, status: 'draft', subtotal_cents: 0, vat_cents: 0, total_cents: 5_000, created_at: 2.days.ago)
    Estimate.create!(patient: patient, status: 'sent',  subtotal_cents: 0, vat_cents: 0, total_cents: 3_000, created_at: 120.days.ago)

    s = dashboard_stats
    expect(s).to include('estimates_pipeline', 'estimates_awaiting')
    expect(s['estimates_awaiting']).to eq(1)
    expect(s['estimates_pipeline']).to eq(50.0)
  end

  it 'does not count accepted estimates in the pipeline' do
    Estimate.create!(patient: patient, status: 'accepted', subtotal_cents: 0, vat_cents: 0, total_cents: 9_900, created_at: 1.day.ago)
    expect(dashboard_stats['estimates_awaiting']).to eq(0)
  end
end
