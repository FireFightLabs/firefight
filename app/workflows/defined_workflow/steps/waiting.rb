# How long a step that waits on a person waits, in its own settings: Ask a person, Approval and Manual step. Past it the
# step takes its route for nobody answering. A step saved before it said so waits as long as its time limit, or a day.
module DefinedWorkflow::Steps::Waiting
  KEY_WAIT = "wait_minutes".freeze
  DEFAULT_MINUTES = 1_440
  FEWEST_MINUTES = 5
  MOST_MINUTES = 10_080
  HOUR = 60
  DAY = 1_440

  def self.included(base) = base.extend(ClassMethods)

  module ClassMethods
    def waits? = true

    def wait_help = "#{KEY_WAIT} (how long it waits, in minutes, #{FEWEST_MINUTES} to #{MOST_MINUTES.to_fs(:delimited)}, a day when left out)"

    def wait_problems(config, named)
      given = config[KEY_WAIT]
      return [] if given.nil?
      return [] if given.is_a?(Integer) && given.between?(FEWEST_MINUTES, MOST_MINUTES)

      [ "#{named} waits from #{words(FEWEST_MINUTES)} to #{words(MOST_MINUTES)}, as a whole number of minutes." ]
    end

    def wait_limit(config, timeout_seconds: nil)
      minutes = config[KEY_WAIT]
      return minutes.minutes if minutes.is_a?(Integer) && minutes.positive?

      ActiveSupport::Duration.build(timeout_seconds || DEFAULT_MINUTES.minutes.to_i)
    end

    # A wait as a person says it, such as 7 days or 90 minutes, in its largest whole unit.
    def words(minutes)
      return "#{minutes / DAY} #{'day'.pluralize(minutes / DAY)}" if (minutes % DAY).zero?
      return "#{minutes / HOUR} #{'hour'.pluralize(minutes / HOUR)}" if (minutes % HOUR).zero?

      "#{minutes} #{'minute'.pluralize(minutes)}"
    end
  end

  def handed_off_limit = self.class.wait_limit(@config, timeout_seconds: @step.timeout_seconds)

  def wait_words = self.class.words((handed_off_limit.to_i / 60.0).ceil)
end
