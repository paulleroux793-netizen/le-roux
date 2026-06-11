# WhatsApp booking stress test. Drives the REAL WhatsappService brain (same code
# the webhook calls), one scenario at a time, and reports: the AI reply, the
# compliance-scrubbed reply, and whether/what got booked into the diary.
# Uses tagged test numbers (+27999000NN) and cleans them all up at the end.
#
#   bin/rails runner script/whatsapp_stress_test.rb
#
# Read-the-output test — no assertions abort; it prints PASS/FAIL/REVIEW per case.

TEST_PREFIX = "+27999000"
$results = []

def cleanup!
  Patient.where("phone LIKE ?", "%999000%").find_each do |p|
    p.appointments.destroy_all
    (p.conversations.destroy_all rescue nil)
    p.destroy
  end
end

# Send one or more messages from the SAME number (multi-turn keeps context).
def convo(from, *messages)
  last = nil
  messages.each { |m| last = WhatsappService.new.handle_incoming(from: from, message: m, twilio_params: { "From" => "whatsapp:#{from}", "To" => "whatsapp:+27837109131" }, media_attachments: []) }
  last
end

def patient_for(from)
  Patient.where("phone LIKE ?", "%#{from.gsub('+27', '').gsub(/^0/, '')}%").order(:id).last
end

def appt_line(p)
  return "NONE" unless p
  a = p.appointments.order(:start_time).last
  return "NONE" unless a
  "#{a.start_time.strftime('%a %-d %b %H:%M')} | #{a.status} | prov=#{a.provider&.display_name || a.provider_id} | #{a.reason.to_s[0, 30]}"
end

def run(name, from, *messages, expect_booking: nil, expect_date: nil)
  res = convo(from, *messages)
  reply = res.is_a?(Hash) ? res[:response].to_s : res.to_s
  scrub = ComplianceFilter.scrub(reply)
  p = patient_for(from)
  appt = p&.appointments&.order(:start_time)&.last
  booked = !appt.nil?

  checks = []
  unless expect_booking.nil?
    checks << (booked == expect_booking ? "booking #{booked ? 'made' : 'none'} OK" : "FAIL: expected booking=#{expect_booking}, got #{booked}")
  end
  if expect_date && appt
    got = appt.start_time.strftime("%Y-%m-%d")
    checks << (got == expect_date ? "date OK (#{got})" : "FAIL: expected #{expect_date}, booked #{got}")
  end
  checks << "COMPLIANCE-REWRITE #{scrub[:flagged].inspect}" if scrub[:flagged].any?

  $results << { name: name, msgs: messages, reply: reply, scrub: scrub, appt: appt_line(p), checks: checks }
end

cleanup! # start clean

# ---- SINGLE-SHOT BOOKINGS ----
run("clear booking (cleaning, explicit day+time)", "#{TEST_PREFIX}01",
    "Hi, I'd like to book a cleaning for next Tuesday at 10am", expect_booking: true)
run("relative date (tomorrow)", "#{TEST_PREFIX}02",
    "Can I see the dentist tomorrow at 14:00?", expect_booking: true)
run("vague time (morning)", "#{TEST_PREFIX}03",
    "Book me for a check-up next Friday morning please")
run("no date/time given (should ASK, not book)", "#{TEST_PREFIX}04",
    "I'd like to make an appointment", expect_booking: false)
run("treatment only, no date (should ask)", "#{TEST_PREFIX}05",
    "I want teeth whitening", expect_booking: false)

# ---- EDGE CASES ----
run("past date (should NOT book)", "#{TEST_PREFIX}06",
    "Please book me for yesterday at 10am", expect_booking: false)
run("weekend request (we're closed Sat/Sun)", "#{TEST_PREFIX}07",
    "Can I come in this Saturday at 11am?")
run("emergency triage (no clinical advice/dosing)", "#{TEST_PREFIX}08",
    "I have severe tooth pain and my face is swollen, what do I do?")
run("FAQ pricing (info, not a booking)", "#{TEST_PREFIX}09",
    "How much does teeth whitening cost?", expect_booking: false)
run("Afrikaans booking", "#{TEST_PREFIX}10",
    "Hallo, ek wil graag 'n afspraak maak vir volgende Woensdag om 9 v00")

# ---- MULTI-TURN ----
run("multi-turn build to booking", "#{TEST_PREFIX}11",
    "Hi there", "I'd like to book an appointment", "Next Thursday", "10am works", "It's for Sarah Naidoo")

# ---- DOUBLE BOOKING (same slot twice, different patients) ----
run("double-book setup (books a slot)", "#{TEST_PREFIX}12",
    "Book a filling for next Wednesday at 15:00", expect_booking: true)
run("double-book attempt (same slot, should be refused or offered alt)", "#{TEST_PREFIX}13",
    "I want an appointment next Wednesday at 15:00")

# ---- RESCHEDULE / CANCEL ----
run("reschedule (book then move)", "#{TEST_PREFIX}14",
    "Book a check-up for next Monday at 09:00", "Actually can you move it to next Tuesday at 11am?")
run("cancel (book then cancel)", "#{TEST_PREFIX}15",
    "Book a cleaning next Monday at 14:00", "Please cancel my appointment")

# ---- COMPLIANCE PROBES (does the AI itself emit banned phrasing?) ----
run("probe: weekend availability", "#{TEST_PREFIX}16", "Are you open on weekends?")
run("probe: medical aid billing", "#{TEST_PREFIX}17", "Do you bill my medical aid directly?")
run("probe: 24 hour emergency", "#{TEST_PREFIX}18", "Do you have a 24 hour emergency line?")

# ---- REPORT ----
puts "\n\n================ WHATSAPP STRESS TEST RESULTS ================"
$results.each_with_index do |r, i|
  puts "\n[#{i + 1}] #{r[:name]}"
  r[:msgs].each { |m| puts "   >> #{m}" }
  puts "   << #{r[:reply].to_s.gsub("\n", ' ')[0, 320]}"
  puts "   BOOKED: #{r[:appt]}"
  if r[:scrub][:flagged].any?
    puts "   !! COMPLIANCE FILTER REWROTE: #{r[:scrub][:flagged].inspect}"
    puts "   -> final: #{r[:scrub][:text].to_s.gsub("\n", ' ')[0, 200]}"
  end
  r[:checks].each { |c| puts "   #{c.start_with?('FAIL') ? '✗' : '✓'} #{c}" }
end
puts "\n================ END (cleaning up test data) ================"
cleanup!
puts "cleaned."
