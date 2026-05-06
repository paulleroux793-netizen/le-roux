class MorningConfirmationJob < ApplicationJob
  queue_as :default

  def perform
    # Per v2 practice config: morning confirmation requests via WhatsApp
    # are deferred — practice does these manually via phone. Flip
    # send_day_before_confirm_request in practice_config.yml + redeploy
    # to re-enable.
    unless PracticeConfig.confirmations_and_reminders[:send_day_before_confirm_request]
      Rails.logger.info("[MorningConfirmation] Skipped — send_day_before_confirm_request is disabled in practice_config.yml")
      return
    end

    ConfirmationService.new.run_daily_confirmations
  end
end
