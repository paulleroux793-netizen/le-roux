# Real intake form templates for Dr Chalita le Roux Inc — the three forms a new
# patient completes on their phone (via a tokenised WhatsApp link) BEFORE arriving.
#
#   1. patient_details      — patient + responsible party + medical aid + emergency contact
#   2. health_questionnaire — medical history (conditional "if yes → details")
#   3. consent_treatment    — treatment consent info + acknowledgement
#
# Print-and-sign workflow: NO digital signature is captured. On arrival reception
# prints the pre-filled IntakePdf and the patient signs + initials each page BY HAND.
# Hence `requires_signature: false` on all three.
#
# The `schema` jsonb drives the React intake wizard. Shape:
#   { intro:, sections: [ { key:, title:, fields: [ field, ... ] } ] }
# A field is:
#   { key:, label:, type:, required:, help?:, options?:, reveal_when?: }
# Field types the wizard renders: text, tel, email, date, id_number, select,
#   textarea, yesno (boolean), checkbox, heading, statement (read-only copy).
# `reveal_when: { field: "<key>", equals: <value> }` shows a field only when an
#   earlier answer matches — used for the "if yes, give details" follow-ups.
#
# Idempotent + versioned: editing a template here means bumping its `version`
# (a new active row); old submissions keep pointing at the version they used.
#   bundle exec rails runner db/seeds/intake_forms.rb

def upsert_template!(key:, name:, version:, schema:)
  tpl = FormTemplate.find_or_initialize_by(key: key, version: version)
  tpl.name = name
  tpl.schema = schema
  tpl.active = true
  tpl.requires_signature = false # print-and-sign; wet signature on the printout
  tpl.save!
  # Retire older active versions of the same key so `FormTemplate.latest(key)`
  # always returns this one.
  FormTemplate.where(key: key, active: true).where.not(id: tpl.id).update_all(active: false)
  tpl
end

# ── 1. Patient & account details ──────────────────────────────────────────────
upsert_template!(
  key: "patient_details",
  name: "Patient & Account Details",
  version: 1,
  schema: {
    intro: "Please complete your details before your visit. This saves time at " \
           "reception — when you arrive we print the form and you sign it.",
    sections: [
      {
        key: "patient",
        title: "Patient details",
        fields: [
          { key: "title", label: "Title", type: "select", required: false,
            options: %w[Mr Mrs Ms Miss Dr Prof Master] },
          { key: "first_name", label: "First name", type: "text", required: true },
          { key: "last_name",  label: "Surname",    type: "text", required: true },
          { key: "date_of_birth", label: "Date of birth", type: "date", required: false },
          # The ONE required identifier. Accepts a SA ID OR a passport (foreign patients),
          # so it's a free-text field, not numeric-only. Stored in patients.id_number,
          # which is designed to hold "SA ID / passport / DOB+zeros for kids".
          { key: "id_number", label: "ID or passport number", type: "text", required: true,
            help: "Your South African ID number — or your passport number if you are not a South African citizen." },
          { key: "contact_number", label: "Contact number", type: "tel", required: false },
          { key: "email", label: "Email address", type: "email", required: false,
            help: "We email your settled account here so you can claim back from your medical aid." }
        ]
      },
      {
        key: "responsible_person",
        title: "Person responsible for the account",
        fields: [
          { key: "rp_same_as_patient", label: "Same as patient", type: "yesno", required: false },
          { key: "rp_title", label: "Title", type: "select", required: false,
            options: %w[Mr Mrs Ms Miss Dr Prof Master],
            reveal_when: { field: "rp_same_as_patient", equals: false } },
          { key: "rp_first_name", label: "First name", type: "text", required: false,
            reveal_when: { field: "rp_same_as_patient", equals: false } },
          { key: "rp_last_name", label: "Surname", type: "text", required: false,
            reveal_when: { field: "rp_same_as_patient", equals: false } },
          { key: "rp_home_address", label: "Home address", type: "textarea", required: false },
          { key: "rp_home_phone", label: "Home tel / cell number", type: "tel", required: false },
          { key: "rp_employer", label: "Employer", type: "text", required: false },
          { key: "rp_work_address", label: "Work address", type: "textarea", required: false },
          { key: "rp_work_phone", label: "Work tel number", type: "tel", required: false },
          { key: "rp_postal_address", label: "Postal address", type: "textarea", required: false },
          { key: "rp_email", label: "Email", type: "email", required: false }
        ]
      },
      {
        key: "medical_aid",
        title: "Medical aid details",
        fields: [
          { key: "has_medical_aid", label: "Do you have a medical aid?", type: "yesno", required: false },
          { key: "scheme_name", label: "Medical aid", type: "text", required: false,
            reveal_when: { field: "has_medical_aid", equals: true } },
          { key: "scheme_plan", label: "Medical aid plan / option", type: "text", required: false,
            reveal_when: { field: "has_medical_aid", equals: true } },
          { key: "member_number", label: "Medical aid number", type: "text", required: false,
            reveal_when: { field: "has_medical_aid", equals: true } },
          { key: "dependent_code", label: "Dependent code", type: "text", required: false,
            reveal_when: { field: "has_medical_aid", equals: true } },
          { key: "main_member", label: "Main member name", type: "text", required: false,
            reveal_when: { field: "has_medical_aid", equals: true } },
          { key: "main_member_id", label: "Main member ID number", type: "id_number", required: false,
            reveal_when: { field: "has_medical_aid", equals: true } }
        ]
      },
      {
        key: "emergency_contact",
        title: "Nearest family / emergency contact",
        fields: [
          { key: "emergency_contact_name", label: "Name", type: "text", required: false },
          { key: "emergency_contact_phone", label: "Contact number", type: "tel", required: false }
        ]
      }
    ]
  }
)

# ── 2. Health questionnaire ───────────────────────────────────────────────────
# Each illness / medication is a yes/no; "Allergies" and "Other" reveal a detail box.
ILLNESSES = [
  %w[bp High\ /\ low\ blood\ pressure],
  %w[angina Angina],
  ["rheumatic_fever", "Rheumatic / scarlet fever"],
  ["congenital_heart", "Congenital heart disease"],
  ["respiratory", "Asthma / bronchitis / emphysema / TB"],
  ["liver", "Jaundice / hepatitis / other liver disease"],
  ["kidney", "Kidney disease"],
  ["diabetes", "Diabetes"],
  ["epilepsy", "Epilepsy"],
  ["bleeding", "Bleeding tendency"],
  ["anemia", "Anemia"],
  ["arthritis", "Arthritis"],
  ["muscular", "Muscular disease"]
].freeze

MEDICATIONS = [
  ["med_cortisone", "Cortisone / other steroids"],
  ["med_antidepressants", "Anti-depressants"],
  ["med_sedatives", "Tranquilizers / sedatives"],
  ["med_anticoagulants", "Anti-coagulants / blood thinners"],
  ["med_antihypertensives", "Blood pressure / anti-hypertensives"],
  ["med_thyroid", "Thyroid drugs"],
  ["med_contraceptives", "Contraceptives"],
  ["med_bisphosphonate", "Bisphosphonate treatment / bone density"]
].freeze

upsert_template!(
  key: "health_questionnaire",
  name: "Health Questionnaire",
  version: 1,
  schema: {
    intro: "Your medical history helps us treat you safely. Please answer honestly — " \
           "everything here is confidential and kept as part of your clinical record.",
    sections: [
      {
        key: "illnesses",
        title: "Do you have, or have you had, any of the following?",
        fields: ILLNESSES.map { |key, label| { key: key, label: label, type: "yesno", required: false } } + [
          { key: "allergies_flag", label: "Allergies", type: "yesno", required: false },
          { key: "allergies", label: "Please list your allergies", type: "textarea", required: false,
            reveal_when: { field: "allergies_flag", equals: true } },
          { key: "other_illness_flag", label: "Any other illness or condition", type: "yesno", required: false },
          { key: "other_illness", label: "Please describe", type: "textarea", required: false,
            reveal_when: { field: "other_illness_flag", equals: true } }
        ]
      },
      {
        key: "medications",
        title: "Are you currently taking, or have you taken, any of the following?",
        fields: MEDICATIONS.map { |key, label| { key: key, label: label, type: "yesno", required: false } } + [
          { key: "other_medication_flag", label: "Any other medication", type: "yesno", required: false },
          { key: "other_medication", label: "Please list", type: "textarea", required: false,
            reveal_when: { field: "other_medication_flag", equals: true } }
        ]
      },
      {
        key: "other_history",
        title: "A few more questions",
        fields: [
          { key: "prosthesis_flag", label: "Do you have any artificial prosthesis? (heart valves / knees / hips)",
            type: "yesno", required: false },
          { key: "prosthesis", label: "Please describe", type: "textarea", required: false,
            reveal_when: { field: "prosthesis_flag", equals: true } },
          { key: "anaesthesia_reaction_flag",
            label: "Have you or any family member had complications or unusual reactions to local / general anaesthesia?",
            type: "yesno", required: false },
          { key: "anaesthesia_reaction", label: "Please describe", type: "textarea", required: false,
            reveal_when: { field: "anaesthesia_reaction_flag", equals: true } },
          { key: "pregnant", label: "Female patients: are you pregnant or trying to get pregnant?",
            type: "yesno", required: false }
        ]
      }
    ]
  }
)

# ── 3. Treatment consent (informational; initialled + signed on paper) ─────────
# The numbered clauses are read on the phone; the patient physically initials each
# one and signs on the printout. Digitally we capture a single acknowledgement that
# they have read and understood, so reception knows it was reviewed in advance.
CONSENT_CLAUSES = [
  ["X-rays", "I understand X-rays may be needed to diagnose and plan my treatment."],
  ["Drugs and medications",
   "I understand that antibiotics, analgesics and other medications can cause allergic reactions, " \
   "ranging from redness, swelling, itching and vomiting to, rarely, severe anaphylactic shock."],
  ["Changes in treatment plan",
   "I understand that during treatment it may be necessary to change or add procedures because of " \
   "conditions found while working that were not discovered during examination. I give permission for " \
   "the dentist to make any changes and additions as necessary."],
  ["Removal of teeth",
   "Alternatives to removal have been explained to me. I understand the risks of having teeth removed, " \
   "including pain, swelling, infection, dry socket, and numbness (paraesthesia) that can last an " \
   "indefinite period, and that further treatment by a specialist may be needed."],
  ["Crowns, bridges and caps",
   "I understand it is not always possible to match the colour of natural teeth exactly, that I may wear " \
   "temporary crowns, and that the final opportunity to make changes is before cementation."],
  ["Dentures, complete or partial",
   "I understand that wearing dentures can be difficult, that immediate dentures may be painful and need " \
   "several relines, and that a permanent reline (at additional cost) may be needed later."],
  ["Endodontic treatment (root canal)",
   "I realise there is no guarantee root canal treatment will save my tooth, and that complications can " \
   "occur, including the need for additional surgical procedures."],
  ["Periodontal loss (tissue & bone)",
   "I understand that care must be exercised when chewing on fillings, and that more expensive treatment " \
   "may be required due to additional decay or sensitivity."],
  ["Fillings",
   "I understand sensitivity is common after a newly placed filling, and that a more expensive filling or " \
   "further treatment may be required due to additional decay."]
].freeze

upsert_template!(
  key: "consent_treatment",
  name: "Dental Treatment Consent",
  version: 2, # supersedes the v1 demo stub
  schema: {
    intro: "Please read the following before your visit. When you arrive you will initial each point " \
           "and sign — this is a legal and binding consent to treatment.",
    sections: [
      {
        key: "clauses",
        title: "Treatment consent",
        fields: CONSENT_CLAUSES.flat_map.with_index do |(heading, body), i|
          [
            { key: "clause_#{i}_heading", label: "#{i + 1}. #{heading}", type: "heading" },
            { key: "clause_#{i}_body", label: body, type: "statement" }
          ]
        end
      },
      {
        key: "acknowledgement",
        title: "Acknowledgement",
        fields: [
          { key: "general_statement", type: "statement",
            label: "I understand that dentistry is not an exact science and that reputable practitioners " \
                   "cannot fully guarantee results. I acknowledge that no guarantee has been made regarding " \
                   "the treatment I have requested and authorised." },
          { key: "payment_statement", type: "statement",
            label: "This practice is contracted OUT of medical-aid tariffs and requires immediate payment " \
                   "for all services rendered. A settled account will be emailed to me so I can claim back " \
                   "from my medical aid. EFTs and month-end payments are not available." },
          { key: "acknowledged",
            label: "I have read and understood the above, and will sign and initial the printed form on arrival.",
            type: "checkbox", required: true }
        ]
      }
    ]
  }
)

puts "Intake form templates ready: #{FormTemplate.active.where(key: %w[patient_details health_questionnaire consent_treatment]).pluck(:key, :version).map { |k, v| "#{k} v#{v}" }.join(', ')}"
