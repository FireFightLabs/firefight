module Operator
  # The console's access to SolidWorkflow's tables. The rest of the app uses the engine only through workflow classes.
  # This returns the engine's own records, so the console calls the engine's own pause, resume, cancel, retry and skip.
  module WorkflowRuns
    STATES = SolidWorkflow::Workflow.states.keys.freeze
    STATE_FAILED = SolidWorkflow::Workflow.states.fetch("failed")
    STATE_PAUSED = SolidWorkflow::Workflow.states.fetch("paused")
    STEP_STATUSES = SolidWorkflow::Step.statuses.keys.freeze
    FAILURE_EVENTS = [
      SolidWorkflow::Events::Workflow::FAILED, SolidWorkflow::Events::Step::FAILED, SolidWorkflow::Events::Step::ATTEMPT_FAILED
    ].freeze

    def self.recent(state: nil, kind: nil)
      scope = SolidWorkflow::Workflow.includes(:steps, :subject).order(created_at: :desc, id: :desc)
      scope = scope.where(state: state) if STATES.include?(state.to_s)
      kind.present? ? scope.where(workflow_class: kind) : scope
    end

    def self.kinds = SolidWorkflow::Workflow.distinct.order(:workflow_class).pluck(:workflow_class)

    def self.counts_by_state = SolidWorkflow::Workflow.group(:state).count

    def self.find(id) = SolidWorkflow::Workflow.includes(:steps, :subject, events: :step).find(id)

    def self.find_step(id) = SolidWorkflow::Step.includes(:workflow).find(id)

    def self.for_subject(subject) = SolidWorkflow::Workflow.where(subject: subject).includes(:steps)

    # Runs started in the window. With a workspace, only runs for that workspace's incidents.
    def self.started(since, workspace: nil)
      scope = SolidWorkflow::Workflow.where(created_at: since..)
      workspace ? scope.where(subject_type: Incident.name, subject_id: workspace.incidents.select(:id)) : scope
    end

    def self.window_counts(since, workspace: nil) = started(since, workspace:).group(:state).count

    # Steps waiting to retry after a failure.
    def self.retrying_count(since, workspace: nil)
      SolidWorkflow::Step.pending.where(workflow_id: started(since, workspace:).select(:id)).where("attempts > 0").count
    end

    def self.failed_in(since, workspace: nil, limit:)
      started(since, workspace:).failed.includes(:steps, :subject).order(updated_at: :desc).limit(limit)
    end

    # Runs whose id starts with the query.
    def self.starting_with(query, limit:)
      SolidWorkflow::Workflow.includes(:subject).where(Finder.id_starts(SolidWorkflow::Workflow.arel_table, query)).limit(limit)
    end

    # Active runs with no update for longer than the engine's stuck threshold, whatever the window.
    def self.stuck(workspace: nil, limit:)
      scope = SolidWorkflow::Workflow.stuck.includes(:subject).order(:updated_at).limit(limit)
      workspace ? scope.where(subject_type: Incident.name, subject_id: workspace.incidents.select(:id)) : scope
    end

    # Failed step counts per incident.
    def self.failed_steps_by_incident(incident_ids)
      SolidWorkflow::Step.joins(:workflow).failed
                         .where(solid_workflow_workflows: { subject_type: Incident.name, subject_id: incident_ids })
                         .group("solid_workflow_workflows.subject_id").count
    end
  end
end
