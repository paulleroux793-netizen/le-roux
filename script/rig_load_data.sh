#!/usr/bin/env bash
# Idempotent data load for Ivory on the rig. Run from the repo dir on the rig:
#   bash script/rig_load_data.sh
# Loads reference data, imports the real 2046 patients from GoodX, then encrypts PHI.
# Every step is idempotent and safe to re-run. Reads Elixir/GoodX source READ-ONLY.
set -euo pipefail
DC="docker compose -f docker-compose.rig.yml"
run() { echo; echo "==> $*"; $DC exec -T web bash -lc "$*"; }

# 1. Reference data (procedure codes, macros, schemes, ICD-10, intake forms, mics)
run "bundle exec rails runner db/seeds/practice_management.rb"
run "bundle exec rails runner db/seeds/medical_schemes.rb"
run "bundle exec rails runner db/seeds/icd10_codes.rb"
run "bundle exec rails runner db/seeds/intake_forms.rb"
run "bundle exec rails runner db/seeds/recording_devices.rb"

# 2. Real patient import (GoodX demographics CSV -> patients/accounts/schemes)
run "bundle exec rails runner 'PatientDemographicsImporter.new.call(dry_run: false)'"

# 3. Encrypt PHI in place (id numbers, medical history, intake data), then verify
run "bundle exec rails phi:encrypt"
run "bundle exec rails phi:verify"

# 4. Quick counts
run "bundle exec rails runner 'puts %{patients=#{Patient.count} accounts=#{BillingAccount.count} schemes=#{MedicalScheme.count} procedure_codes=#{ProcedureCode.count} macros=#{TreatmentMacro.count}}'"
echo; echo "DATA_LOAD_DONE"
