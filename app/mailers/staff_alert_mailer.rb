class StaffAlertMailer < ApplicationMailer
  # Internal alert email sent to reception when the AI flags a conversation
  # for human follow-up. Multi-channel: also goes via SMS + (eventually)
  # WhatsApp template once the production sender + flagged-alert template
  # are approved.
  def flagged(patient_name:, patient_phone:, reason:, conversation_url: nil)
    @patient_name = patient_name
    @patient_phone = patient_phone
    @reason = reason
    @conversation_url = conversation_url

    mail(
      to: PracticeConfig.practice[:email],
      subject: "[AI Flagged] #{patient_name} (#{patient_phone}) — needs reception"
    )
  end
end
