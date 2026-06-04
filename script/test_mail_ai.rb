# Manual end-to-end test of the AI email assistant (real Claude call), draft-only.
#   docker compose -f docker-compose.rig.yml exec -T web bundle exec rails runner script/test_mail_ai.rb
acct = MailAccount.first
abort "no mail account" unless acct

thr = MailThread.create!(mail_account: acct, provider_thread_id: "test-ai-#{Time.now.to_i}",
                         subject: "Booking request", participants: [ "john@example.com" ],
                         last_message_at: Time.current, folder: "INBOX")
msg = MailMessage.create!(mail_account: acct, mail_thread: thr,
                          provider_message_id: thr.provider_thread_id, folder: "INBOX",
                          from_address: "john@example.com", from_name: "John Smith",
                          subject: "Booking request",
                          body_text: "Hi, this is John Smith. I'd like to book a teeth cleaning appointment for next Tuesday at 10am please. My number is 0821234567. Thanks!",
                          snippet: "Hi, this is John Smith...", received_at: Time.current, sent_by_us: false)

draft = MailAiAssistant.new.draft_for(msg)

if draft
  puts "=== AI EMAIL DRAFT (nothing sent) ==="
  puts "intent:         #{draft.extraction_metadata['intent']}"
  puts "thread_intent:  #{thr.reload.clinical_intent}"
  puts "requested_start:#{draft.requested_start_time}"
  puts "reason:         #{draft.requested_reason}"
  puts "confidence:     #{draft.confidence}"
  puts "draft_reply:"
  puts draft.extraction_metadata["draft_reply"].to_s.lines.first(8).join
else
  puts "NO DRAFT produced (check classification/intent)"
end

# cleanup
draft&.destroy
msg.destroy
thr.destroy
puts "\n(cleaned up test data)"
