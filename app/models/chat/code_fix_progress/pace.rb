# The first word and the last always go, news between at most once an interval, a repeat never. It is asked on every
# read of the agent, so news held back still goes out once the agent goes quiet.
class Chat::CodeFixProgress::Pace
  def initialize(every:)
    @every = every.to_f
    @sent = {}
  end

  def due?(key, work, now: Time.current.to_f)
    last = @sent[key]
    return false if last && last[:signature] == work.signature
    return false if last && !work.finished? && now - last[:at] < @every

    @sent[key] = { at: now, signature: work.signature }
    true
  end
end
