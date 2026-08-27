module SolidWorkflow
  class Base
    include SolidWorkflow::IdempotentSteps

    class << self
      def registry
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

      def step(name, depends_on: [], retry_config: nil, queue: nil)
        steps << {
          name: name.to_s,
          depends_on: Array(depends_on).map(&:to_s),
          retry_config: retry_config,
          queue: queue&.to_s
        }
      end

      def steps
        @steps ||= []
      end

      def start!(subject, context: {})
        wf = create_workflow!(subject, context)
        wf.enqueue_next_steps
        wf
      end

      def start_inline!(subject, context: {}, max_iterations: 100)
        wf = create_workflow!(subject, context)
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

      def create_workflow!(subject, context)
        if steps.empty?
          raise ArgumentError, "#{name} must define at least one step. Use the 'step' DSL method to define workflow steps."
        end

        validate_steps!

        SolidWorkflow::Workflow.transaction do
          wf = SolidWorkflow::Workflow.create!(
            name: workflow_name,
            workflow_class: name,
            subject_type: subject.class.name,
            subject_id: subject.id,
            context: context,
            state: :pending,
            workflow_config: workflow_config
          )

          steps.each_with_index do |step_def, index|
            merged_retry = (step_def[:retry_config] || default_retry_config).dup
            merged_retry["queue"] = step_def[:queue] if step_def[:queue]

            wf.steps.create!(
              name: step_def[:name],
              depends_on: step_def[:depends_on],
              status: :pending,
              position: index,
              retry_config: merged_retry,
              max_attempts: step_def.dig(:retry_config, :max_attempts) || SolidWorkflow.max_default_attempts
            )
          end

          wf.record_event(SolidWorkflow::Events::Workflow::STARTED)
          wf
        end
      end

      def default_retry_config
        { max_attempts: SolidWorkflow.max_default_attempts, backoff: SolidWorkflow::Step::Retryable::BACKOFF_EXPONENTIAL }
      end

      # A duplicate name corrupts the dependency map (index_by(&:name)), an
      # unknown or cyclic dependency hangs the workflow forever instead of
      # erroring, catch all three at start! time.
      def validate_steps!
        names = steps.map { |s| s[:name] }

        duplicates = names.tally.select { |_, count| count > 1 }.keys
        raise ArgumentError, "#{name} defines duplicate step names: #{duplicates.join(', ')}" if duplicates.any?

        steps.each do |step_def|
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
