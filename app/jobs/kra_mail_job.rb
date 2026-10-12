# Sends one KRA notification mail through krai. Runs in the app process
# (:async) so it works without a separate job worker; a failed mail is only
# logged and never affects the SMS or the submission.
class KraMailJob < ApplicationJob
  self.queue_adapter = :async unless Rails.env.test?

  def perform(kind, params)
    KraMailRelay.deliver!(kind, params)
  rescue StandardError => error
    Rails.logger.error("KraMailRelay failed kind=#{kind} to=#{params['to_email']}: #{error.class} #{error.message}")
  end
end
