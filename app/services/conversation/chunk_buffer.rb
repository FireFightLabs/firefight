# Sends text in pieces, since a call per token would flood the socket and the platform's rate limit.
# whole_markup cuts a piece only at a space with no link, bold or code left open before it, for a platform that renders
# each piece's markup on its own, so a link cut in two never shows as raw characters. Text with no such space yet waits,
# unless it grew past LONG_HELD, when it goes as it is.
class Conversation::ChunkBuffer
  INTERVAL = 0.25.seconds
  MAX_CHARS = 200
  LONG_HELD = 2_000
  CODE_FENCE = /^[ \t]*```/
  # A link, an angle bracket link or a link's address still open at the end of the text, a label with spaces included,
  # until its closing delimiter. A lone < in prose opens nothing, so only one that starts a Slack link counts.
  OPEN_LINK = /(?:\[[^\]\n]*|\]\([^)\n]*|<(?:https?:|mailto:|[@#!])[^>\n]*)\z/
  INLINE_CODE = /`[^`\n]*`/

  def initialize(interval: INTERVAL, max_chars: MAX_CHARS, whole_markup: false, &send_text)
    @interval = interval
    @max_chars = max_chars
    @whole_markup = whole_markup
    @send_text = send_text
    @held = +""
    @sent_at = Time.current
    @open_through = 0
  end

  def add(text)
    @held << text
    return unless @held.length >= @max_chars || Time.current - @sent_at >= @interval

    @whole_markup ? flush_whole_markup! : flush!
  end

  def flush!
    send_held(@held.length)
  end

  private

  def flush_whole_markup!
    cut = last_safe_cut
    return send_held(cut) if cut
    return flush! if @held.length > LONG_HELD

    @open_through = @held.length
    nil
  end

  # Just past the last space or line break that closes everything opened before it, or nil. A space already found open
  # stays open, since the text before it does not change, so only the spaces added since are tried.
  def last_safe_cut
    spaces = []
    @held.scan(/\s/) { spaces << Regexp.last_match.end(0) }
    spaces.reverse_each.take_while { |cut| cut > @open_through }.find { |cut| closed?(@held[0, cut]) }
  end

  def closed?(text)
    fences = text.each_line.count { |line| line.match?(CODE_FENCE) }
    return false if fences.odd?

    outside_code = text.gsub(/```.*?```/m, "")
    return false if outside_code.count("`").odd?

    # Markers inside a closed inline code span are literal, so they open no bold and no link.
    prose = outside_code.gsub(INLINE_CODE, "")
    prose.scan("**").size.even? && !prose.rstrip.match?(OPEN_LINK)
  end

  def send_held(length)
    return if length.zero?

    text = @held[0, length]
    @held = @held[length..]
    @open_through = 0
    @sent_at = Time.current
    @send_text.call(text)
  end
end
