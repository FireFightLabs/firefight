# The facts for a question nobody has declared an incident for, which are only what was asked. What is open, what fired
# and which services exist are for the agent to look up when the question needs them.
class Investigation::QuestionSeed
  def initialize(investigation)
    @investigation = investigation
  end

  def gather
    {
      Investigation::Seeding::KEY_GATHERED_AT => Time.current.iso8601,
      "question" => @investigation.question,
      "brief" => @investigation.brief.presence
    }.compact
  end
end
