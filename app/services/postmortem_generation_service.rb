# Saves the engine's draft as the incident's postmortem and announces it, and
# starts a generation for every entry point, so the placeholder and the job
# are created the same way whether the ask came from a button, a command, the
# dashboard, the API or an agent.
class PostmortemGenerationService
  UNAVAILABLE_MESSAGE = "AI features are not available.".freeze
  UNKNOWN_MEMBER_MESSAGE = "Could not identify your workspace membership.".freeze

  # What a person is told after asking. started is false when nothing was
  # enqueued and the message says why, true when a generation is running,
  # whether this ask started it or found it already under way.
  Outcome = Struct.new(:started, :message, keyword_init: true)

  def self.started_message(incident)
    "Generating postmortem for #{incident.identifier}... This may take a minute."
  end

  def initialize(workspace)
    @workspace = workspace
  end

  # The guards every Slack door runs before starting, in one place, so a
  # button, a command and the home menu cannot drift on what they refuse.
  def request!(incident, by:)
    return Outcome.new(started: false, message: UNAVAILABLE_MESSAGE) unless defined?(FirefightAi)

    gate = Entitlements.check(@workspace, Entitlements::AI)
    return Outcome.new(started: false, message: gate.message) if gate.blocked?

    return Outcome.new(started: true, message: self.class.started_message(incident)) if incident.postmortem&.generating?

    blocked_reason = incident.postmortem_blocked_reason
    return Outcome.new(started: false, message: blocked_reason) if blocked_reason

    start!(incident, by: by)
    Outcome.new(started: true, message: self.class.started_message(incident))
  end

  # Returns the placeholder when this call is the one that enqueued the job,
  # nil when a generation was already running.
  def start!(incident, by:)
    postmortem = Postmortem.start_generation!(incident, by: by)
    PostmortemGenerationJob.perform_later(incident.id) if postmortem
    postmortem
  end

  def generate!(incident, generated_by:)
    draft = FirefightAi::PostmortemGenerator.new(@workspace).generate(incident)
    postmortem = Postmortem.complete_generation!(incident, draft, generated_by: generated_by)
    announce(incident, postmortem)
    OnboardingWalkthroughService.new(@workspace).advance!(incident)
    postmortem
  end

  private

  def announce(incident, postmortem)
    return if incident.channel_id.blank?

    adapter = WorkspaceAdapter.for(@workspace)
    result = adapter.post_postmortem_message(
      channel_id: incident.channel_id,
      incident: incident,
      postmortem: postmortem
    )
    postmortem.update!(message_ts: result[:message_id])
    adapter.pin_message(channel_id: incident.channel_id, message_id: result[:message_id])
  end
end
