# Saves the engine's draft as the incident's postmortem and announces it.
class PostmortemGenerationService
  def initialize(workspace)
    @workspace = workspace
  end

  def generate!(incident, generated_by:)
    draft = FirefightAi::PostmortemGenerator.new(@workspace).generate(incident)
    postmortem = Postmortem.complete_generation!(incident, draft, generated_by: generated_by)
    announce(incident, postmortem)
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
