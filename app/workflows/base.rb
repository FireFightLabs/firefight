class Workflows::Base
  include IdempotentSteps

  class << self
    # Define workflow name
    def workflow_name(val = nil)
      @workflow_name = val if val
      @workflow_name || name
    end

    # Define workflow config
    def workflow_config(val = nil)
      @workflow_config = val if val
      @workflow_config || {}
    end


    # Define a step
    def step(name, depends_on: [], retry_config: nil)
      steps << {
        name: name.to_s,
        depends_on: Array(depends_on).map(&:to_s),
        retry_config: retry_config
      }
    end

    # Get all steps
    def steps
      @steps ||= []
    end

    # Start a workflow asynchronously
    #
    # Creates workflow and enqueues orchestration job.
    # Steps execute in background jobs via Solid Queue.
    #
    # This is the default method for starting workflows in production,
    # development, and console.
    #
    # @param subject [ActiveRecord::Base] The subject record (e.g., Incident, User)
    # @param context [Hash] Immutable context/configuration for the workflow
    # @return [Workflow] The created workflow instance
    #
    # @example Production usage
    #   workflow = IncidentCreationWorkflow.start!(incident)
    #   # Steps execute in background jobs
    #
    # @example Console debugging
    #   # Use start_inline! instead for synchronous execution
    #   workflow = IncidentCreationWorkflow.start_inline!(incident)
    #
    def start!(subject, context: {})
      wf = create_workflow!(subject, context)
      wf.enqueue_next_steps
      wf
    end

    # Start workflow synchronously
    #
    # Executes entire workflow synchronously in a loop without background jobs.
    # Useful for:
    # - Tests (avoid dealing with job queues)
    # - Console debugging (see results immediately)
    # - Troubleshooting workflow issues
    #
    # @param subject [ActiveRecord::Base] The subject record
    # @param context [Hash] Immutable context for the workflow
    # @return [Workflow] The completed workflow instance
    #
    # @example In tests
    #   workflow = MyWorkflow.start_inline!(user)
    #   expect(workflow.state).to eq("succeeded")
    #
    # @example In console
    #   workflow = IncidentCreationWorkflow.start_inline!(incident)
    #   # => Executes immediately, no background jobs
    #
    def start_inline!(subject, context: {})
      wf = create_workflow!(subject, context)

      max_iterations = 100 # Prevent infinite loops
      iteration = 0

      loop do
        iteration += 1
        raise "Workflow exceeded max iterations (#{max_iterations})" if iteration > max_iterations

        wf.reload
        steps = wf.workflow_steps.reload.to_a

        # Find ready steps
        ready = steps.select { |s| s.ready_to_run?(steps) }
        break if ready.empty?

        # Execute ready steps synchronously
        ready.each do |step|
          step.populate_input!(steps)
          Workflows::RunStepJob.new.perform(step.id)
        end

        # Update workflow state (without debounce)
        wf.enqueue_next_steps

        wf.reload
        break if wf.completed?
      end

      wf.reload
    end

    private

    def create_workflow!(subject, context)
      Workflow.transaction do
        wf = Workflow.create!(
          name: workflow_name,
          workflow_class: name,
          subject_type: subject.class.name,
          subject_id: subject.id,
          context: context,
          state: :pending,
          workflow_config: workflow_config
        )

        # Create steps
        steps.each_with_index do |step_def, index|
          wf.workflow_steps.create!(
            name: step_def[:name],
            depends_on: step_def[:depends_on],
            status: :pending,
            position: index,
            retry_config: step_def[:retry_config] || default_retry_config,
            max_attempts: step_def.dig(:retry_config, :max_attempts) || 5
          )
        end

        wf.record_event(WorkflowEvents::Workflow::STARTED)
        wf
      end
    end

    def default_retry_config
      { max_attempts: 5, backoff: WorkflowStep::Retryable::BACKOFF_EXPONENTIAL }
    end
  end

  # Run a specific step
  def run_step(step_name, workflow:, step:, input: {})
    raise "Unknown step: #{step_name}" unless respond_to?(step_name)
    public_send(step_name, workflow: workflow, step: step, input: input)
  end
end
