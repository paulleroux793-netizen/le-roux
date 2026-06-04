# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # PHI / POPIA — never write patient-identifying or health data to logs. In
  # development Rails logs full params, so these MUST be filtered on the rig too.
  :id_number, :data, :signature_data, :allergies, :chronic_conditions,
  :current_medications, :dental_notes, :medical_notes, :transcript, :transcript_text,
  :phone, :phone_number, :first_name, :last_name, :date_of_birth, :dob,
  :emergency_contact_name, :emergency_contact_phone, :insurance_policy_number,
  :membership_number, :address, :answers
]
