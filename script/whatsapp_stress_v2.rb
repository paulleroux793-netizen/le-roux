# Diverse WhatsApp stress scenarios (v2) — different from v1. Probes the
# reliability fixes: duplicate sends, offered-slot confirmation, number replies,
# typos, change-of-mind, cross-patient conflict, "did it work?", whitening.
# Drives the real WhatsappService brain; cleans up tagged test numbers (+27991...).

def clean
  Patient.where("phone LIKE ?", "%9910%").or(Patient.where("phone LIKE ?", "%9911%")).find_each do |p|
    p.appointments.each { |a| (Notification.where(appointment_id: a.id).delete_all rescue nil); (ConfirmationLog.where(appointment_id: a.id).delete_all rescue nil) }
    p.appointments.destroy_all; (p.conversations.destroy_all rescue nil); p.destroy
  end
end

def say(from, msg)
  r = WhatsappService.new.handle_incoming(from: from, message: msg,
        twilio_params: { "From" => "whatsapp:#{from}", "To" => "whatsapp:+27837109131" }, media_attachments: [])
  (r.is_a?(Hash) ? r[:response] : r).to_s
end

def appts(from)
  p = Patient.where("phone LIKE ?", "%#{from.delete('+')[2..]}%").order(:id).last
  p ? p.appointments.where.not(status: :cancelled).order(:start_time).to_a : []
end

def show(label, from, *msgs)
  reply = nil
  msgs.each { |m| reply = say(from, m); puts "  >> #{m}" }
  a = appts(from)
  puts "  << #{reply.to_s.gsub("\n",' ')[0,220]}"
  puts "  BOOKINGS: #{a.map { |x| x.start_time.strftime('%a %-d %b %H:%M') + '/' + x.status }.join(', ').presence || 'none'}"
  a
end

clean
puts "================ WHATSAPP STRESS V2 ================"

puts "\n[A] DUPLICATE send (same booking twice, sequential) — expect 1 booking + 2nd = already-booked"
show("A", "+27991000001", "Book a cleaning next Tuesday at 10am", "Book a cleaning next Tuesday at 10am")

puts "\n[B] TYPO-heavy booking — expect a booking"
show("B", "+27991000002", "hi i wud like 2 book a chekup nex wednsday at 11")

puts "\n[C] Full-sentence with name+new+treatment+vague time"
show("C", "+27991000003", "Hi, I'm Thabo Nkosi, a new patient, I need a filling — can I come Friday around 2pm?")

puts "\n[D] OFFERED-SLOT confirmation: too-soon today -> offers slots -> 'the first one'"
soon = (Time.zone.now + 10.minutes).strftime("%H:%M")
show("D", "+27991000004", "Can I book a cleaning today at #{soon}?", "the first one please")

puts "\n[E] NUMBER reply after offer"
show("E", "+27991000005", "Can I book a check-up today at #{soon}?", "2")

puts "\n[F] CHANGE OF MIND mid-flow"
show("F", "+27991000006", "Book a check-up Tuesday at 9am", "actually make it Wednesday at 11am instead")

puts "\n[G] WHITENING (deposit -> pending_confirmation)"
show("G", "+27991000007", "I'd like teeth whitening next Thursday at 3pm")

puts "\n[H] 'DID IT WORK?' after a booking — must NOT rebook, must reassure"
show("H", "+27991000008", "Book a cleaning next Monday at 2pm", "is my appointment confirmed?")

puts "\n[I] CROSS-PATIENT conflict (B takes A's slot) — expect B refused + alternatives, 0 new for B"
say("+27991100001", "Book a filling next Wednesday at 14:00")  # patient A books
bA = appts("+27991100001")
rB = say("+27991100002", "I want an appointment next Wednesday at 14:00")  # patient B same slot
bB = appts("+27991100002")
puts "  A booked: #{bA.map { |x| x.start_time.strftime('%a %H:%M') }.join}; B reply: #{rB.gsub("\n",' ')[0,140]}"
puts "  B bookings (expect none at 14:00): #{bB.map { |x| x.start_time.strftime('%a %H:%M') }.join(', ').presence || 'none'}"

puts "\n[J] GIBBERISH — graceful, no booking"
show("J", "+27991000009", "asdfgh qwerty ???")

puts "\n[K] RESCHEDULE with no existing appointment — graceful"
show("K", "+27991000010", "please move my appointment to Friday")

puts "\n[L] Afrikaans multi-turn booking"
show("L", "+27991000011", "Haai", "Ek wil 'n skoonmaak bespreek vir volgende Dinsdag om 14:00")

puts "\n================ cleaning up ================"
clean
puts "cleaned."
