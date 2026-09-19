# Sends text in pieces, since a call per token would flood the socket and the platform's rate limit.
class Conversation::ChunkBuffer
  INTERVAL = 0.25.seconds
  MAX_CHARS = 200

  def initialize(interval: INTERVAL, max_chars: MAX_CHARS, &send_text)
    @interval = interval
    @max_chars = max_chars
    @send_text = send_text
    @held = +""
    @sent_at = Time.current
  end

  def add(text)
    @held << text
    flush! if @held.length >= @max_chars || Time.current - @sent_at >= @interval
  end

  def flush!
    return if @held.empty?

    text = @held
    @held = +""
    @sent_at = Time.current
    @send_text.call(text)
  end
end
