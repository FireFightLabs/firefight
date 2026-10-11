# The one world a replay's tools all read: the scenario's facts as they stand and how often each answer was given.
# A change moves it on, and so does a read whose answer says time passed or the person saying something new, so two
# tools reading the same run never tell two stories, and a read after a change shows what the change left.
class Conversation::BenchCase::World
  attr_reader :facts, :used

  def initialize(bench_case)
    @case = bench_case
    @facts = bench_case.world.dup
    @used = Hash.new(0)
  end

  # Answers a call and moves the world on: the answer is counted and what it sets becomes true. Nil when nothing in the
  # scenario answers it.
  def answer!(name, arguments)
    found, index = @case.answer_for(name, arguments, self)
    return unless found

    @used[index] += 1 if index
    advance!(found.sets)
    found
  end

  # What a call would answer now, changing nothing, as a watch reads what it follows.
  def peek(name, arguments) = @case.answer_for(name, arguments, self)&.first

  def advance!(sets) = @facts.merge!(Conversation::BenchCase.facts(sets))

  def holds?(state) = state.all? { |name, value| @facts[name.to_s].to_s.casecmp?(value.to_s) }
end
