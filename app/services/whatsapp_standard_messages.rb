# Builds the practice's four standard WhatsApp messages in the EXACT wording reception uses
# (per Dr Chalita's live WhatsApp): Location, Directions, Intake form, and the booking
# Confirmation (with this appointment's date/time in Africa/Johannesburg). These are PURE string
# builders — the actual sending is done by the controller via WhatsappTemplateService#send_text,
# so this is fully testable without touching Twilio. Reception triggers the real sends.
class WhatsappStandardMessages
  INTAKE_URL = "https://intake.chalitaleroux.co.za/intake/new".freeze
  MAP_LINK   = "https://maps.app.goo.gl/3iHKg7AMa8qRcfLf6".freeze
  TZ         = "Africa/Johannesburg".freeze

  # 1 — Location (Google Maps)
  def self.location
    "Dr Chalita le Roux · Office Park, Corner of Doreen Rd and Lawrence Rd, Amorosa, Roodepoort, 2040\n\n#{MAP_LINK}"
  end

  # 2 — Directions (both common approach roads)
  def self.directions
    "Directions from Hendrik Potgieter Rd:\n" \
      "Turn onto Doreen Rd,\n" \
      "We are on your left-hand side at the second robot.\n\n" \
      "Directions from CR Swart Rd:\n" \
      "Turn onto Doreen Rd,\n" \
      "We are on your right-hand side at the first robot."
  end

  # 3 — Secure intake form link
  def self.intake
    "Secure Patient Form — Dr Chalita le Roux | Roodepoort\n" \
      "Complete your details, medical history and consent securely in about 5 minutes on your phone. Paperless.\n" \
      "#{INTAKE_URL}"
  end

  # 4 — Booking confirmation with this appointment's weekday + date + time
  def self.confirmation(appointment)
    t = appointment.start_time.in_time_zone(TZ)
    "Good afternoon,\n\n" \
      "Appointment has been booked for\n" \
      "#{t.strftime('%A')}\n" \
      "#{t.strftime('%-d %B %Y')}\n" \
      "#{t.strftime('%H:%M')}\n\n" \
      "Please arrive 10 minutes before your appointment to open a file.\n\n" \
      "Looking forward to seeing you,\n" \
      "Dr Chalita & team 🌸🌿"
  end

  # Location + directions combined into ONE message (Paul's preference 2026-06-12) — the
  # maps card and the road directions belong together. The intake form and the booking
  # confirmation stay as their own messages so each is a clear, separate signal to the patient.
  def self.location_and_directions
    "#{location}\n\n#{directions}"
  end

  # The standard pack, in send order — now three messages: (1) where we are + how to get
  # here, (2) the secure intake form to complete, (3) the booking confirmation.
  def self.pack(appointment)
    [ location_and_directions, intake, confirmation(appointment) ]
  end
end
