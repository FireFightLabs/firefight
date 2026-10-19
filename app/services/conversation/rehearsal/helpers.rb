# The reads a replayed chat's helpers hold: every scenario tool that reads, answered through the scenario's world as
# Halon's own calls are, so a run_helpers call in a replay runs real helpers rather than a report someone wrote. Helpers
# run at once on threads of their own, so every call through the world is taken one at a time, under the same lock as
# the specialists'.
class Conversation::Rehearsal::Helpers
  # Said to a helper that calls a general tool in a way that would change something.
  ONLY_READS = "Not run. A helper only reads, so say in your report what you would change and why.".freeze
  # Tools a replay hands Halon itself, which a helper never holds.
  HALONS_ONLY = [ Chat::Helper::RUN_HELPERS, Chat::Helper::ASK_SPECIALIST, Chat::Tools::Open.tool_name, Chat::Tools::UseSkill.tool_name ].freeze

  # recorded builds a scenario tool for a chat (Conversation::Rehearsal#recorded).
  def initialize(bench_case, recorded:, lock:)
    @case = bench_case
    @recorded = recorded
    @lock = lock
  end

  def tools(agent)
    held = @case.tools.select { |definition| HALONS_ONLY.exclude?(definition.name) && Conversation::Rehearsal::Specialists.reads?(definition) }.map do |definition|
      guard = Conversation::Rehearsal::Specialists.guard_of(definition)
      tool = @recorded.call(definition, agent.chat)
      if guard
        Conversation::Rehearsal::Specialists::Guarded.new(tool, definition, guard, @lock, refused: ONLY_READS)
      else
        Conversation::Rehearsal::Specialists::Reading.new(tool, definition, @lock, refused: ONLY_READS)
      end
    end
    held + [ Chat::Tools::ReadResult.new(agent) ]
  end
end
