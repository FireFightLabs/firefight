module SolidWorkflow
  class Base
    include SolidWorkflow::IdempotentSteps

    class << self
      # One registry for every class, however deep it inherits, such as a host's subclass of the interpreter.
      def registry
        return SolidWorkflow::Base.registry unless equal?(SolidWorkflow::Base)

        @registry ||= {}
      end

      def inherited(subclass)
        super
        registry[subclass.name] = subclass
      end

      def workflow_name(val = nil)
        @workflow_name = val if val
        @workflow_name || name
      end

      def workflow_config(val = nil)
        @workflow_config = val if val
        @workflow_config || {}
      end

      # on_failure: continue lets the steps that depend on this one run once it has failed for good, and the run
      # carries on past the failure, as a defined step's does.
      def step(name, depends_on: [], retry_config: nil, queue: nil, on_failure: SolidWorkflow::Definition::ON_FAILURE_STOP)
        steps << {
          name: name.to_s,
          depends_on: Array(depends_on).map(&:to_s),
          retry_config: retry_config,
          queue: queue&.to_s,
          on_failure: on_failure.to_s
        }
      end

      def steps
        @steps ||= []
      end

      # Whether the host lets a run of this class move now. Asked before any step is claimed or enqueued and by the
      # sweeper, so a run held back keeps its place and carries on once let.
      def runnable?(_workflow) = true

      # Told of every event a run of this class records, so a host can keep its own record of the run.
      def observe(_workflow, _event); end

      # What a finished run hands back to whoever started it.
      def result_of(_workflow) = nil

      # Step data on its way into a stored row, so a host can redact it.
      def clean(data, workflow:, step:) = data

      # Step kinds the host runs, beside the engine's own.
      def action_kinds = []

      # One start key gives one run, however many times it is started.
      def start!(subject, context: {}, start_key: nil)
        wf = create_workflow!(subject, context, start_key: start_key)
        wf.enqueue_next_steps
        wf
      end

      def start_inline!(subject, context: {}, max_iterations: 100, start_key: nil)
        wf = create_workflow!(subject, context, start_key: start_key)
        drain_inline!(wf, max_iterations: max_iterations)
      end

      # Runs every step that is ready, then the ones that became ready, in this process, until none is.
      def drain_inline!(wf, max_iterations: 100)
        iteration = 0

        loop do
          iteration += 1
          raise "Workflow exceeded max iterations (#{max_iterations})" if iteration > max_iterations

          wf.reload
          all_steps = SolidWorkflow::Step.where(workflow_id: wf.id).order(:position).to_a

          step_map = all_steps.index_by(&:name)
          ready = all_steps.select { |s| s.ready_to_run?(step_map) }
          break if ready.empty?

          ready.each do |step|
            all_steps = SolidWorkflow::Step.where(workflow_id: wf.id).order(:position).to_a
            step = all_steps.find { |s| s.id == step.id }

            step.populate_input!(all_steps)
            SolidWorkflow::RunStepJob.new.perform(step.id)
          end

          wf.enqueue_next_steps

          wf.reload
          break if wf.completed?
        end

        wf.reload
      end

      private

      def create_workflow!(subject, context, start_key: nil, **options)
        if start_key && (existing = SolidWorkflow::Workflow.find_by(start_key: start_key))
          return existing
        end

        rows = step_rows(**options)
        if rows.empty?
          raise ArgumentError, "#{name} must define at least one step. Use the 'step' DSL method to define workflow steps."
        end

        SolidWorkflow::Workflow.transaction(requires_new: true) do
          wf = SolidWorkflow::Workflow.create!(
            name: workflow_name,
            workflow_class: name,
            subject_type: subject.class.name,
            subject_id: subject.id,
            context: context,
            state: :pending,
            workflow_config: workflow_config,
            start_key: start_key,
            **workflow_attributes(**options)
          )

          rows.each_with_index do |row, index|
            wf.steps.create!(row.merge(status: row[:status] || :pending, position: index))
          end

          wf.record_event(SolidWorkflow::Events::Workflow::STARTED)
          wf
        end
      rescue ActiveRecord::RecordNotUnique
        raise unless start_key

        SolidWorkflow::Workflow.find_by!(start_key: start_key)
      end

      def workflow_attributes(**) = {}

      def step_rows(**)
        validate_steps!

        steps.map do |step_def|
          merged_retry = (step_def[:retry_config] || default_retry_config).dup
          merged_retry["queue"] = step_def[:queue] if step_def[:queue]

          {
            name: step_def[:name],
            depends_on: step_def[:depends_on],
            on_failure: step_def[:on_failure],
            retry_config: merged_retry,
            max_attempts: step_def.dig(:retry_config, :max_attempts) || SolidWorkflow.max_default_attempts
          }
        end
      end

      def default_retry_config
        { max_attempts: SolidWorkflow.max_default_attempts, backoff: SolidWorkflow::Step::Retryable::BACKOFF_EXPONENTIAL }
      end

      # A duplicate name corrupts the dependency map and an unknown or cyclic dependency
      # hangs the workflow forever, so all three are caught at start!.
      def validate_steps!
        names = steps.map { |s| s[:name] }

        duplicates = names.tally.select { |_, count| count > 1 }.keys
        raise ArgumentError, "#{name} defines duplicate step names: #{duplicates.join(', ')}" if duplicates.any?

        steps.each do |step_def|
          # A class step has no edges, so there is no error route to take.
          allowed = [ SolidWorkflow::Definition::ON_FAILURE_STOP, SolidWorkflow::Definition::ON_FAILURE_CONTINUE ]
          unless allowed.include?(step_def[:on_failure])
            raise ArgumentError, "#{name} step '#{step_def[:name]}' has on_failure '#{step_def[:on_failure]}', which is not one of #{allowed.join(', ')}"
          end

          unknown = step_def[:depends_on] - names
          raise ArgumentError, "#{name} step '#{step_def[:name]}' depends on unknown step(s): #{unknown.join(', ')}" if unknown.any?
        end

        detect_dependency_cycle!
      end

      def detect_dependency_cycle!
        deps = steps.to_h { |s| [ s[:name], s[:depends_on] ] }
        visited = Set.new
        visiting = Set.new

        visit = lambda do |step_name, path|
          return if visited.include?(step_name)
          if visiting.include?(step_name)
            raise ArgumentError, "#{name} has a dependency cycle: #{(path + [ step_name ]).join(' → ')}"
          end

          visiting << step_name
          deps[step_name].each { |dep| visit.call(dep, path + [ step_name ]) }
          visiting.delete(step_name)
          visited << step_name
        end

        deps.each_key { |step_name| visit.call(step_name, []) }
      end
    end

    def run_step(step_name, workflow:, step:, input: {})
      raise "Unknown step: #{step_name}" unless respond_to?(step_name)
      public_send(step_name, workflow: workflow, step: step, input: input)
    end
  end
end
