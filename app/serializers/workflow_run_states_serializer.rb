# The newest run of the version the canvas shows, as Last run lays it over the steps: how each step stood and how long it
# took, without what it read or gave.
class WorkflowRunStatesSerializer < BaseSerializer
  object_as :run

  type :string
  def id
    run.id
  end

  type "#{Workflow::Run::STATUSES.map(&:inspect).join(' | ')}"
  def status
    run.status
  end

  type :boolean
  def test
    run.test?
  end

  type :string
  def created_at
    run.created_at.iso8601
  end

  type "{ stepKey: string; iteration: string; status: #{Workflow::Run::Step::STATUSES.map(&:inspect).join(' | ')}; startedAt: string | null; finishedAt: string | null; waitingApproval: boolean }[]"
  def steps
    run.steps.map do |step|
      { stepKey: step.step_key, iteration: step.iteration, status: step.status, startedAt: step.started_at&.iso8601,
        finishedAt: step.finished_at&.iso8601, waitingApproval: step.waiting_approval? }
    end
  end
end
