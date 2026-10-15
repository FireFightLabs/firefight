# Streamed words with every chart marker left out, for a place that shows the answer as it is written and has no chart
# to put there, such as a Slack thread. A marker can arrive in pieces, so the tail that could still become one is held
# until the next words show it is not. A line that held only markers goes with its line break, and no more than one
# blank line is left where it stood.
class Chat::Chart::Marker::Stream
  # The start of a marker still arriving, at the very end of the words so far.
  PARTIAL = /#{Chat::Chart::Marker::ARRIVING}\z/i

  def initialize(&emit)
    @emit = emit
    @held = +""
    @line_start = true
    @trailing_breaks = 0
    @dropped = false
  end

  def add(text)
    @held << text.to_s
    last_break = @held.rindex("\n")
    whole_lines = last_break ? @held[..last_break] : +""
    rest = last_break ? @held[(last_break + 1)..] : @held
    shown = without_markers(whole_lines)
    @held = hold(rest)
    shown << without_inline(rest.delete_suffix(@held))
    emit(shown)
  end

  def finish
    shown = without_markers(@held)
    @held = +""
    emit(shown)
  end

  private

  # A line that so far holds only markers, or a marker's start, is kept whole, since its line break decides whether it
  # goes. Otherwise only a marker's start at the very end is kept.
  def hold(rest)
    left = rest.gsub(Chat::Chart::Marker::PATTERN, "")
    return rest.dup if rest.match?(Chat::Chart::Marker::PATTERN) && left.strip.empty?

    cut = rest.index(PARTIAL)
    return +"" unless cut
    return rest.dup if rest[...cut].strip.empty?

    rest[cut..]
  end

  # A line only drops whole when it starts a line of the answer, never the tail of one already shown.
  def without_markers(text)
    return without_inline(text) unless text.match?(Chat::Chart::Marker::PATTERN)

    @dropped = true
    first_break = @line_start ? 0 : (text.index("\n") || text.size - 1) + 1
    without_inline(text[...first_break]) + without_inline(text[first_break..].gsub(Chat::Chart::Marker::ALONE, ""))
  end

  def without_inline(text)
    return text.dup unless text.match?(Chat::Chart::Marker::PATTERN)

    @dropped = true
    text.gsub(Chat::Chart::Marker::INLINE, "")
  end

  def emit(shown)
    shown = squeezed(shown) if @dropped
    return if shown.empty?

    @line_start = shown.end_with?("\n")
    breaks = shown[/\n*\z/].size
    @trailing_breaks = breaks == shown.size ? @trailing_breaks + breaks : breaks
    @emit.call(shown)
  end

  # Once a marker went, at most one blank line is left in a row, counting what was already shown.
  def squeezed(shown)
    leading = shown[/\A\n*/].size
    allowed = [ 2 - @trailing_breaks, 0 ].max
    shown = shown[(leading - allowed)..] if leading > allowed
    shown.gsub(/\n{3,}/, "\n\n")
  end
end
