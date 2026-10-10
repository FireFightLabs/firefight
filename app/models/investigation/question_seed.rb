# The facts for a question nobody has declared an incident for, which are only what was asked. What is open, what fired
# and which services exist are for the agent to look up when the question needs them.
class Investigation::QuestionSeed
  # A security event started the run, so nobody asked and nobody may be watching, as with a run an alert started. It has no
  # incident to page on yet, so the answer offers one when the secret still works or is public.
  KEY_SECURITY_EVENT = "security_event".freeze
  SECURITY_SKILL = "leaked_secret".freeze

  def initialize(investigation)
    @investigation = investigation
  end

  def gather
    {
      Investigation::Seeding::KEY_GATHERED_AT => Time.current.iso8601,
      "question" => @investigation.question,
      "brief" => @investigation.brief.presence,
      KEY_SECURITY_EVENT => (security_facts if @investigation.trigger_source == Investigation::TRIGGER_SECURITY_EVENT)
    }.compact
  end

  private

  def security_facts
    {
      "started_from" => "A connected provider reported this and started this run. Nobody asked, and nobody may be watching yet.",
      "skill" => SECURITY_SKILL,
      "incident" => "There is no incident yet. When the secret still works or is public, set suggest_incident, so the team is offered to " \
                    "declare one, which is how whoever is on call is paged."
    }
  end
end
