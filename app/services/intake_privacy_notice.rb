# POPIA s18 notification ("privacy notice") shown before the patient fills the intake
# forms, and reprinted on the IntakePdf. Drafted for the treating-practice basis: under
# POPIA s27 + s32 a registered practice may process health information for treatment and
# practice administration WITHOUT separate consent, so this is a NOTICE, not a consent wall.
#
# Information Officer = Dr Chalita le Roux (locked 2026-06-03). Cross-border wording
# reflects EU-region hosting (GDPR adequacy supports the s72 transfer).
#
# Returns an array of { title:, body: } so the React page and the PDF render identically.
class IntakePrivacyNotice
  INFORMATION_OFFICER = "Dr Chalita le Roux"
  PRACTICE_NAME = "Dr Chalita le Roux Inc"
  PRACTICE_ADDRESS = "Unit 2, Amorosa Office Park, 68 Lawrence Road, Amorosa, Roodepoort, 2040"
  CONTACT_EMAIL = "info@drchalitaleroux.co.za"

  def self.sections
    [
      { title: "Who collects your information",
        body: "These forms are collected by #{PRACTICE_NAME}, a dental practice registered in " \
              "South Africa at #{PRACTICE_ADDRESS}. Our Information Officer is #{INFORMATION_OFFICER} " \
              "(#{CONTACT_EMAIL})." },

      { title: "Why we collect it",
        body: "We process your personal and health information to assess your suitability for dental " \
              "treatment, to provide and manage your care, to keep clinical records as required by law " \
              "and the HPCSA, to communicate with you about appointments, and to manage billing. We are " \
              "contracted out of medical-aid tariffs — you pay the practice directly and we email you a " \
              "settled account so you can claim back from your scheme." },

      { title: "What we collect",
        body: "Your identification details (including your SA ID or passport number), contact details, " \
              "medical-aid details, medical and dental history, current medications, allergies, and an " \
              "emergency contact." },

      { title: "Is it required?",
        body: "Some information is required for us to treat you safely and to meet our legal obligations. " \
              "If you do not provide it, we may not be able to provide or continue treatment. Fields that " \
              "are optional are not marked as required." },

      { title: "Who can see it",
        body: "Only authorised staff and treating practitioners involved in your care, and our IT service " \
              "providers (secure hosting and messaging) who act under written agreements and may process " \
              "your data only on our instructions. We share with your medical scheme or other providers " \
              "only where necessary for your treatment or where you authorise it." },

      { title: "Where it is stored",
        body: "Your records are stored on secure servers hosted in the European Union, which provides data " \
              "protection comparable to South Africa's. Some messaging is handled by providers outside South " \
              "Africa under contracts that require POPIA-equivalent protection." },

      { title: "How long we keep it",
        body: "We keep your clinical records for at least the minimum periods required by law and the HPCSA " \
              "— currently at least 6 years from your last treatment for adults, and longer for minors or " \
              "where clinically or legally indicated." },

      { title: "Your rights",
        body: "You may request access to your information, ask us to correct it, object to processing such as " \
              "direct marketing, and lodge a complaint with the Information Regulator (South Africa). Contact " \
              "our Information Officer at #{CONTACT_EMAIL}." }
    ]
  end

  # One-line acknowledgement shown next to the "I understand" control.
  def self.acknowledgement
    "I have read the privacy notice above and understand how my information will be used and protected."
  end
end
