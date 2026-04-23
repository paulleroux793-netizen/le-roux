class PracticeSettings < ApplicationRecord
  validates :name, presence: true

  def self.instance
    first || create!(
      name:               "Dr Chalita le Roux Inc",
      phone:              ENV.fetch("TWILIO_WHATSAPP_NUMBER", ""),
      email:              ENV.fetch("MAILER_FROM_ADDRESS", "reception@drchalitaleroux.co.za"),
      address_line1:      "Unit 2, Amorosa Office Park",
      address_line2:      "Corner of Doreen Road & Lawrence Rd",
      city:               "Amorosa, Roodepoort, Johannesburg, 2040",
      map_link:           "https://maps.app.goo.gl/3iHKg7AMa8qRcfLf6",
      emergency_phone:    "071 884 3204",
      price_consultation: AiService::PRICING["consultation"],
      price_check_up:     AiService::PRICING["check_up"],
      price_cleaning:     AiService::PRICING["cleaning"]
    )
  end

  def full_address
    [ address_line1, address_line2, city ].compact_blank.join(", ")
  end

  def admin_mode_for(phone)
    normalized = self.class.normalize_phone(phone)
    (admin_modes || {})[normalized] || "admin"
  end

  def set_admin_mode(phone, mode)
    normalized = self.class.normalize_phone(phone)
    update!(admin_modes: (admin_modes || {}).merge(normalized => mode))
  end

  def self.normalize_phone(phone)
    phone.to_s.gsub(/\D/, "")
  end
end
