module Mcp
  module Tools
    # Writes a workflow, the same shape Halon writes one in a chat. Whoever may publish it, granting its own identity
    # what its steps need, gets it live. A member who may not gets a draft and the workspace admins are asked to publish
    # it, and anyone else, such as an agent, leaves it a draft for an admin.
    class CreateWorkflow < Base
      tool_name CREATE_WORKFLOW
      authorize_as Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_CREATE
      behind_flag FeatureFlags::WORKFLOWS
      description "Make a workflow: something that runs later, on a schedule or by hand, as its own identity with only what an admin " \
                  "grants it. Give a template from the library with its params, or a trigger, steps and edges. Every change carries its " \
                  "undo and is followed by a step that reads how it went. It is published when you may publish it and grant what it " \
                  "needs, otherwise it waits as a draft and the workspace admins are asked. Docs: #{Docs::MCP_SERVER}"
      annotations(**WRITE)
      input_schema(**Workflow::Authoring.schema.deep_symbolize_keys.slice(:properties))

      def self.perform_with_principal(workspace:, principal:, args:)
        workflow = Workflow::Authoring.create!(workspace: workspace, spec: args.to_h, by: (principal if principal.is_a?(WorkspaceMembership)),
                                               reason: "Made over MCP by #{principal.actor_display_name}.")
        draft = workflow.draft
        service = WorkflowPublishService.new(workflow)
        result = if service.may_publish?(draft, by: principal)
          service.publish_through_gateway!(draft, principal: principal, source: AbilityGateway::SOURCE_MCP)
        else
          service.ask_or_leave!(draft, by: principal)
        end
        respond(workflow: Workflow::Listing.summary(workflow.reload), published: workflow.live?, said: result.words)
      rescue Workflow::Authoring::Refused => refused
        Mcp::ToolDispatcher.error_response(refused.message)
      end
    end
  end
end
