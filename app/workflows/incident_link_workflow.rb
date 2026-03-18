class IncidentLinkWorkflow < SolidWorkflow::Base
  workflow_name "incident.link.v1"

  step :post_source_message
  step :post_target_message
  step :update_source_context
  step :update_target_context

  def post_source_message(workflow:, step:, input:)
    return unless workflow.subject.channel_id

    checkpointed(step) do
      source = workflow.subject
      target = target_incident(workflow)
      adapter = adapter_for(workflow)

      case workflow.context["relationship_type"]
      when IncidentRelationship::RELATED
        adapter.post_related_link_message(
          channel_id: source.channel_id,
          source: source,
          target: target,
          linked_by_platform_user_id: workflow.context["linked_by_platform_user_id"]
        )
      when IncidentRelationship::DUPLICATE
        adapter.post_duplicate_source_message(
          channel_id: source.channel_id,
          source: source,
          canonical: target,
          linked_by_platform_user_id: workflow.context["linked_by_platform_user_id"]
        )
      end
    end
  end

  def post_target_message(workflow:, step:, input:)
    return unless target_incident(workflow).channel_id

    checkpointed(step) do
      source = workflow.subject
      target = target_incident(workflow)
      adapter = adapter_for(workflow)

      case workflow.context["relationship_type"]
      when IncidentRelationship::RELATED
        adapter.post_related_link_message(
          channel_id: target.channel_id,
          source: target,
          target: source,
          linked_by_platform_user_id: workflow.context["linked_by_platform_user_id"]
        )
      when IncidentRelationship::DUPLICATE
        adapter.post_duplicate_canonical_message(
          channel_id: target.channel_id,
          source: source,
          canonical: target,
          linked_by_platform_user_id: workflow.context["linked_by_platform_user_id"]
        )
      end
    end
  end

  def update_source_context(workflow:, step:, input:)
    source = workflow.subject
    service = IncidentUpdateService.new(source.workspace)
    service.update_quick_actions(source)
    service.update_announcement(source)
  end

  def update_target_context(workflow:, step:, input:)
    target = target_incident(workflow)
    service = IncidentUpdateService.new(target.workspace)
    service.update_quick_actions(target)
    service.update_announcement(target)
  end

  private

  def target_incident(workflow)
    Incident.find(workflow.context["target_incident_id"])
  end

  def adapter_for(workflow)
    workflow.subject.workspace.adapter
  end
end
