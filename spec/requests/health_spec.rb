require 'rails_helper'

# Locks the /health readiness probe (HealthController). An external uptime monitor relies on
# both the field set and the status↔HTTP-code contract — C8 added db_latency_ms + queue_pending,
# C9 added backup_age_hours + the degraded/503 thresholds. This guards against a future change
# silently dropping a field or breaking the 200/503 contract.
#
# NB: we deliberately do NOT write the ops/last_backup.json marker here — that file is shared with
# the live probe via the bind mount, so mutating it from a test could transiently flip production
# to "degraded". We assert the contract instead, which holds regardless of current backup age.
RSpec.describe 'Health readiness probe', type: :request do
  it 'exposes the full readiness payload with a consistent status/HTTP-code contract' do
    get '/health'

    body = JSON.parse(response.body)
    expect(body.keys).to include('status', 'db', 'db_latency_ms', 'queue_pending', 'backup_age_hours', 'time')

    # The DB is up in the test env, and latency is always a measured number.
    expect(body['db']).to eq(true)
    expect(body['db_latency_ms']).to be_a(Numeric)

    # status is one of the two valid states, and the HTTP code must agree with it.
    expect(%w[ok degraded]).to include(body['status'])
    expect(response.status).to eq(body['status'] == 'ok' ? 200 : 503)
  end

  it 'is reachable without dashboard auth (monitors have no credentials)' do
    get '/health'
    expect(response.status).to be_in([ 200, 503 ]) # never 401
  end
end
