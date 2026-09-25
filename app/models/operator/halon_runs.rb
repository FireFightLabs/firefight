module Operator
  # Halon's runs as the console lists them, and how each one ended. A stop is Halon reaching a limit or a person
  # stopping it, and a failure is something going wrong on our side, which is the one an operator has to look at.
  module HalonRuns
    ENDING_ANSWERED = "answered".freeze
    ENDING_STOPPED = "stopped".freeze
    ENDING_FAILED = "failed".freeze
    ENDING_LIVE = "live".freeze
    ENDINGS = [ ENDING_ANSWERED, ENDING_STOPPED, ENDING_FAILED, ENDING_LIVE ].freeze

    # Limits a run reached, said to the thread in these words. Anything else in error_summary is a cause on our side.
    LIMIT_REASONS = (Investigation::PLAIN_STOP_REASONS - [ Investigation::GAVE_UP ]).freeze

    # The models Halon calls: its runs, their citation re-read, and chat turns.
    FEATURES = [ FirefightAi::Investigator::FEATURE, FirefightAi::CitationCheck::FEATURE, FirefightAi::Responder::FEATURE ].freeze

    def self.ending(status, error_summary)
      return ENDING_LIVE if Investigation::LIVE_STATUSES.include?(status)
      return ENDING_ANSWERED if status == Investigation::STATUS_SUCCEEDED
      return ENDING_STOPPED if status == Investigation::STATUS_CANCELED

      LIMIT_REASONS.include?(error_summary) ? ENDING_STOPPED : ENDING_FAILED
    end

    def self.in(filter)
      filter.scope(Investigation.seen.where(created_at: filter.range))
    end

    def self.list(filter, ending: nil)
      scope = self.in(filter).includes(:workspace, :subject, :finding).order(created_at: :desc, id: :desc)
      ending_scope(scope, ending)
    end

    def self.ending_scope(scope, ending)
      case ending
      when ENDING_LIVE then scope.live
      when ENDING_ANSWERED then scope.where(status: Investigation::STATUS_SUCCEEDED)
      when ENDING_STOPPED
        scope.where(status: Investigation::STATUS_CANCELED)
             .or(scope.where(status: Investigation::STATUS_FAILED, error_summary: LIMIT_REASONS))
      when ENDING_FAILED
        scope.where(status: Investigation::STATUS_FAILED)
             .where("investigations.error_summary IS NULL OR investigations.error_summary NOT IN (?)", LIMIT_REASONS)
      else scope
      end
    end

    # Finished and told the thread it would answer, but the last post never went through.
    def self.not_posted?(run)
      run.over? && run.thread_id.present? && run.answer_posted_at.nil?
    end
  end
end
