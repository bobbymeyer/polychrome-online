class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # A service the job needs that can't be reached (the language model:
  # Remote) is waited for rather than given up on: tried again after 30
  # seconds, then twice as long each time up to every 10 minutes, for about
  # a day. Then the block hears of it, with the job (its arguments) and the
  # last error.
  SERVICE_RETRY_FIRST = 30.seconds
  SERVICE_RETRY_MOST = 10.minutes
  SERVICE_RETRY_ATTEMPTS = 150 # about a day at those gaps

  def self.service_retry_wait(executions)
    (SERVICE_RETRY_FIRST * 2**(executions - 1)).clamp(SERVICE_RETRY_FIRST, SERVICE_RETRY_MOST)
  end

  def self.waits_for_services(&gave_up)
    retry_on Remote::Unreachable, wait: ->(executions) { service_retry_wait(executions) }, attempts: SERVICE_RETRY_ATTEMPTS,
                                  jitter: 0, &gave_up
  end
end
