module Operator
  # Every workspace, and for one the provider its code sandboxes are held to, its failovers and each code fix's sandbox
  # cost beside its AI cost.
  class WorkspacesController < BaseController
    PER_PAGE = 25

    def index
      page = [ params[:page].to_i, 1 ].max
      workspaces = Workspace.order(:name, :id).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a

      render inertia: "operator/workspaces/index", props: {
        workspaces: WorkspaceRowSerializer.many(WorkspaceSandbox.rows(filter, workspaces.first(PER_PAGE))),
        page: page, more: workspaces.size > PER_PAGE,
        **filter_props.except(:workspaces)
      }
    end

    def show
      workspace = Workspace.find(params[:id])
      sandbox = WorkspaceSandbox.new(workspace, filter)

      render inertia: "operator/workspaces/show", props: {
        workspace: { id: workspace.id, name: workspace.name },
        placement: sandbox.placement,
        choices: sandbox.choices.map(&:to_h),
        sandboxMicros: sandbox.sandbox_micros,
        aiMicros: sandbox.ai_micros,
        failoverCount: sandbox.failover_count,
        failovers: SandboxFailoverSerializer.many(sandbox.failovers),
        fixes: SandboxFixSerializer.many(sandbox.fixes),
        **filter_props.except(:workspaces)
      }
    end

    def sandbox
      workspace = Workspace.find(params[:id])
      key = WorkspaceSandbox.key_from(params[:placement])
      blocked = Actions.sandbox_placement_blocked_reason(key)
      return redirect_to(operator_workspace_path(workspace), alert: blocked) if blocked

      workspace.update!(sandbox_provider: key)
      Rails.logger.info({ event: "operator.sandbox_placement", workspace_id: workspace.id, provider: key, operator: operator_label }.to_json)
      redirect_to operator_workspace_path(workspace),
                  notice: key ? "#{workspace.name}'s code sandboxes now run only on #{SandboxProviders.name_of(key)}." : "#{workspace.name}'s code sandboxes follow the deployment's providers again."
    end
  end
end
