# The order a model asked for the calls of one step, for the rows those calls write while they run beside each other
# (FirefightAi::AgentLoop::ToolsTogether). Whoever runs a call hands it its place in fiber storage, which the threads
# the call starts inherit. A row whose order people or the model read, such as an investigation's step number, a chart
# or a saved result, is written in turn, so it lands after the rows of that kind from every call asked before it,
# however long those calls took. A call that is not running beside others has no place and never waits.
module CallOrder
  KEY = :firefight_call_order

  # The calls of one step that run together, by their place in the order asked.
  class Group
    def initialize(size)
      @finished = Array.new(size, false)
      @passed = Array.new(size) { Set.new }
      @lock = Mutex.new
      @changed = ConditionVariable.new
    end

    # Waits until every call asked before place has ended, or has written its first rows of kind when one is named.
    def await(place, kind)
      @lock.synchronize do
        @changed.wait(@lock) until (0...place).all? { |earlier| @finished[earlier] || (kind && @passed[earlier].include?(kind)) }
      end
    end

    def passed(place, kind) = change { @passed[place] << kind }

    def finished(place) = change { @finished[place] = true }

    private

    def change
      @lock.synchronize do
        yield
        @changed.broadcast
      end
    end
  end

  Place = Data.define(:group, :index)

  # Runs one call at its place in the group. However it ends, the calls after it stop waiting for it.
  def self.running(group, index)
    previous = Fiber[KEY]
    Fiber[KEY] = Place.new(group: group, index: index)
    yield
  ensure
    Fiber[KEY] = previous
    group.finished(index)
  end

  # Writes rows of a kind in the order the calls were asked, once every call asked before has written its first rows
  # of that kind or ended, for a row written as a call starts, such as an investigation's step number, so the calls still
  # run together. A call that writes the kind again later in its run, as a capability falling back to a second
  # connection does, may land after a later call's first rows.
  def self.in_turn(kind)
    place = Fiber[KEY]
    return yield unless place

    place.group.await(place.index, kind)
    begin
      yield
    ensure
      place.group.passed(place.index, kind)
    end
  end

  # Writes once every call asked before has ended, for a row written as a call ends, such as a chart, a saved result or
  # a held call, which costs nothing since the step waits for every call anyway.
  def self.after_earlier_calls
    place = Fiber[KEY]
    place&.group&.await(place.index, nil)
    yield
  end
end
