namespace :dev do
  desc <<~DESC
    Create James Bond with a tomorrow appointment and schedule a WhatsApp
    confirmation message to send in 5 minutes.

    Usage:
      rails dev:setup_james_bond_confirmation
      rails dev:setup_james_bond_confirmation PHONE=+27821234567 HOUR=10
  DESC
  task setup_james_bond_confirmation: :environment do
    phone      = ENV.fetch("PHONE", "+27821234567")
    hour       = ENV.fetch("HOUR", "10").to_i
    start_time = Date.tomorrow.to_time.change(hour: hour, min: 0, sec: 0)
    end_time   = start_time + 30.minutes

    patient = Patient.find_or_initialize_by(phone: phone)
    if patient.new_record?
      patient.first_name = "James"
      patient.last_name  = "Bond"
      patient.save!
      puts "Created patient: #{patient.full_name} (#{phone})"
    else
      puts "Found existing patient: #{patient.full_name} (#{phone})"
    end

    appointment = patient.appointments.create!(
      start_time: start_time,
      end_time:   end_time,
      reason:     "Check-up",
      status:     :scheduled
    )
    puts "Created appointment ##{appointment.id}: #{start_time.strftime('%A, %-d %B %Y at %H:%M')}"

    SendAppointmentConfirmationJob.set(wait: 5.minutes).perform_later(appointment.id)
    puts "Confirmation WhatsApp scheduled to send at #{5.minutes.from_now.strftime('%H:%M:%S')} (5 minutes from now)"
  end
end
