# frozen_string_literal: true

# Active Record Encryption for PHI (intake forms): patient ID numbers, medical
# history, and form-submission data.
#
# ── KEYS ──
# The app runs with NO RAILS_MASTER_KEY, so the encryption keys cannot live in
# credentials.yml.enc — they are sourced from the environment here. Generate them
# ONCE and store in ../_shared/.env (and Railway / the Docker env):
#
#   bin/rails db:encryption:init
#   # copy the three values into env as:
#   AR_ENCRYPTION_PRIMARY_KEY=...
#   AR_ENCRYPTION_DETERMINISTIC_KEY=...
#   AR_ENCRYPTION_KEY_DERIVATION_SALT=...
#
# `deterministic_key` is REQUIRED because Patient#id_number is encrypted
# deterministically so it stays searchable (find_by / its unique-ish index).
# Without the keys, every `encrypts` attribute raises on read/write — so set them
# before running the migration. Keys set here only when present, so they never
# clobber a credentials-based config if one is added later.
enc = Rails.application.config.active_record.encryption

enc.primary_key          = ENV["AR_ENCRYPTION_PRIMARY_KEY"]          if ENV["AR_ENCRYPTION_PRIMARY_KEY"].present?
enc.deterministic_key    = ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"]    if ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"].present?
enc.key_derivation_salt  = ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"]  if ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"].present?

# Dev/test convenience: if no keys are supplied, derive stable ones from
# secret_key_base so `encrypts` works out of the box (specs, local dev). PRODUCTION
# always requires the explicit env keys above — never the derived fallback — so a
# leaked/rotated secret_key_base can't silently change how PHI is encrypted.
if enc.primary_key.blank? && !Rails.env.production?
  base = Rails.application.secret_key_base.to_s
  enc.primary_key         = base[0, 32]
  enc.deterministic_key   = base[0, 32]
  enc.key_derivation_salt = base[-32, 32] || base[0, 32]
end

# ── TRANSITION FLAGS (rollout order — REHEARSE on local Docker first) ──
#   1. Deploy with keys set + AR_ENCRYPTION_SUPPORT_UNENCRYPTED=true (default).
#   2. bin/rails db:migrate     # widens columns / converts data jsonb -> text
#   3. bin/rails phi:encrypt    # re-encrypts the 2046 existing patients' PHI in place
#   4. bin/rails phi:verify, then set AR_ENCRYPTION_SUPPORT_UNENCRYPTED=false and
#      redeploy so any stray plaintext is rejected (defence-in-depth).
#
# Support stays ON until explicitly disabled — safe default while the backfill is
# pending (lets Rails READ the existing plaintext rows).
enc.support_unencrypted_data = ENV.fetch("AR_ENCRYPTION_SUPPORT_UNENCRYPTED", "true") == "true"

# Let deterministic finders (e.g. Patient.find_by(id_number:)) match BOTH the
# already-encrypted and not-yet-encrypted rows while the backfill is in flight.
enc.extend_queries = true
