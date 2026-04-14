class MorningConfirmationJob < ApplicationJob
  queue_as :default

  def perform
    ConfirmationService.new.run_daily_confirmations
  end
end
