# What Halon must never learn, checked in code rather than left to the prompt, is a value that is only true now or a
# fact about a person. Both checks lean towards saving, since a setup fact refused is lost while a stray one can be
# rejected, so each needs a clear sign rather than a hint.
module Chat::Memory::Screening
  LIVE_VALUE = "It reads like a live value that will have changed by the next incident, so it is not remembered. " \
               "Remember what it says about the setup instead, without the reading.".freeze
  ABOUT_A_PERSON = "It is about a person, so it is not remembered. Memory holds facts about the setup, and who is on " \
                   "call or who owns what belongs in the catalog.".freeze

  EMAIL = /\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b/
  # An @handle or mention that is not part of an address.
  HANDLE = /(?<![\w.])@[a-z][\w.-]*/i
  DATE = /\b\d{4}-\d{2}-\d{2}(?!\d)|\b\d{1,2}\/\d{1,2}\/\d{2,4}\b|\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]* \d{1,2}(?:st|nd|rd|th)?\b/i
  CLOCK = /\b\d{1,2}:\d{2}(?::\d{2})?\b/
  # A reading such as 850ms, 4.2%, 1200 rps or 3 errors. A port or a version is not one.
  READING = /\b\d+(?:\.\d+)?\s?(?:%|ms|percent|rps|qps|req\/s|requests?\/s|errors?|requests|failures|timeouts|users|connections)(?![\w])/i
  NOW = /\b(?:right now|currently|at the moment|at present|as of now|so far today|this morning|today|tonight)\b/i
  # Readings make up at least this share of the words before a text counts as one.
  READING_SHARE = 0.15

  # Why the text cannot be learned, or nil.
  def self.refusal(workspace, text)
    return LIVE_VALUE if live_value?(text)

    ABOUT_A_PERSON if about_a_person?(workspace, text)
  end

  # A moment rather than a schedule (a date with a time of day), a number said to hold now, or text that is mostly
  # readings. "Backups run at 02:00 UTC" and "Checkout times out after 30s" are setup and pass.
  def self.live_value?(text)
    return true if text.match?(DATE) && text.match?(CLOCK)
    return true if text.match?(NOW) && text.match?(/\d/)

    readings = text.scan(READING).size
    words = text.split.size
    readings >= 2 && readings >= words * READING_SHARE
  end

  # An address, a mention, or a member's name. A full name is matched in any case. A first name only as written, with
  # its capital, and never as the first word of a sentence, so "Max connections is 100" is not read as a person called Max.
  def self.about_a_person?(workspace, text)
    return true if text.match?(EMAIL) || text.match?(HANDLE)

    names(workspace).any? { |name| named?(text, name) }
  end

  def self.named?(text, name)
    pattern = /(?<![[:alnum:]])#{Regexp.escape(name)}(?![[:alnum:]])/
    return text.match?(Regexp.new(pattern.source, Regexp::IGNORECASE)) if name.include?(" ")

    text.to_enum(:scan, pattern).any? do
      before = text[0...Regexp.last_match.begin(0)]
      before.strip.present? && !before.match?(/[.!?]\s*\z/)
    end
  end
  private_class_method :named?

  # The names members are known by, each full name and each first name of three letters or more.
  def self.names(workspace)
    WorkspaceMembership.where(workspace: workspace).includes(:user).flat_map do |member|
      full = [ member.display_name, member.user&.name ].compact_blank.map(&:strip).uniq
      firsts = full.map { |name| name.split.first }.select { |first| first.length >= 3 && first.match?(/\A[[:upper:]]/) }
      (full.select { |name| name.include?(" ") } + firsts).uniq
    end.uniq
  end
end
