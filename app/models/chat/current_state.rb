# How things stand now for a call that was approved some time after it was asked for, as Halon read them just before the
# person decides whether to run it. A chat's held call and a fix's step both keep one.
module Chat::CurrentState
  UNCHANGED = "unchanged"
  CHANGED = "changed"
  DONE_ALREADY = "already_done"
  GONE = "gone"
  # Halon could not read it, or was not there to.
  UNKNOWN = "unknown"
  CHANGES = [ UNCHANGED, CHANGED, DONE_ALREADY, GONE, UNKNOWN ].freeze

  # Said above Halon's own words, so a change is never lost in a sentence.
  WORDS = {
    CHANGED => "Things changed since this was asked for.",
    DONE_ALREADY => "This looks done already.",
    GONE => "What this call changes is gone.",
    UNKNOWN => "Halon could not check how things stand now, so check before you run it."
  }.freeze

  # What Halon read, what kind of change it is, and when it read it.
  Report = Data.define(:state, :change, :checked_at) do
    def initialize(state:, change:, checked_at: Time.current)
      super(state: state.to_s.strip.presence, change: CHANGES.include?(change.to_s) ? change.to_s : UNKNOWN, checked_at: checked_at)
    end

    def warning = WORDS[change]
  end

  # What a person can do with an approved call: run it, dismiss it, or ask again once its approval expired.
  ACTION_RUN = "run"
  ACTION_DISMISS = "dismiss"
  ACTION_ASK_AGAIN = "ask_again"
  ACTIONS = [ ACTION_RUN, ACTION_DISMISS, ACTION_ASK_AGAIN ].freeze

  def self.unknown(reason = nil) = Report.new(state: reason, change: UNKNOWN)
end
