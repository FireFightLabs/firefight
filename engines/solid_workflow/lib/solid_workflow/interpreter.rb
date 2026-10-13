module SolidWorkflow
  # Runs a workflow kept as data. Each run carries a snapshot of its definition, so the steps it runs are the ones it
  # started with whatever the source does after. The engine runs its own control steps (branch, delay, wait for event,
  # for each, join and run workflow), and a host subclass runs the rest by kind and says how references are filled,
  # what data is kept and how a sub workflow starts.
  #
  # A step's config is filled from the run's scope before it runs: the trigger, the inputs and each finished step's
  # output by its name, plus the item and its index inside a for each.
  class Interpreter < Base
    SCOPE_INPUTS = "inputs".freeze
    SCOPE_TRIGGER = "trigger".freeze
    SCOPE_STEPS = "steps".freeze
    SCOPE_ITEM = "item".freeze
    SCOPE_INDEX = "index".freeze
    # The steps of the run a for each item belongs to, finished before the loop began.
    CONTEXT_OUTER_STEPS = "outer_steps".freeze
    # Which item of which loop a run is, outermost first, so a loop inside a loop is told apart.
    CONTEXT_ITERATION = "iteration".freeze
    # Where a delay keeps the moment it waits for, worked out once.
    CHECKPOINT_RESUME_AT = "resume_at".freeze

    class << self
      # Fills a step's config from the run's scope. The engine fills nothing on its own.
      def resolve(value, _scope, workflow:, step:) = value

      def perform(kind, _config, workflow:, step:)
        raise SolidWorkflow::UnknownStepKind, "No step of kind #{kind.inspect} can run"
      end

      # What stands in for a step instead of running it, such as an output pinned while trying a workflow or an earlier
      # run's result when a run starts again from a later step: a Routed for a step that took a route, an output, or nil
      # to run the step.
      def stand_in(_step, workflow:) = nil

      # Starts the run a run_workflow step names, as a run of this class with parent_step: step, and returns it.
      def start_sub_workflow(_config, workflow:, step:)
        raise SolidWorkflow::UnknownStepKind, "#{name} cannot start a sub workflow"
      end

      # Each problem with a definition as a sentence, none when it can run.
      def problems(definition) = SolidWorkflow::Definition.new(definition, action_kinds: action_kinds).problems

      def start!(subject, definition:, context: {}, start_key: nil, not_before: nil, parent_step: nil)
        wf = create_workflow!(subject, context, start_key: start_key, definition: definition, not_before: not_before, parent_step: parent_step)
        wake_at_start(wf, not_before)
        wf.enqueue_next_steps
        wf
      end

      def start_inline!(subject, definition:, context: {}, start_key: nil, max_iterations: 100)
        wf = create_workflow!(subject, context, start_key: start_key, definition: definition)
        drain_inline!(wf, max_iterations: max_iterations)
      end

      # The run's data a step's config is filled from.
      def scope_for(workflow)
        context = workflow.context.to_h
        finished = workflow.steps.select(&:succeeded?).to_h { |step| [ step.label.presence || step.name, step.output ] }
        scope = {
          SCOPE_INPUTS => context[SCOPE_INPUTS] || {},
          SCOPE_TRIGGER => context[SCOPE_TRIGGER] || {},
          SCOPE_STEPS => context[CONTEXT_OUTER_STEPS].to_h.merge(finished)
        }
        scope[SCOPE_ITEM] = context[SCOPE_ITEM] if context.key?(SCOPE_ITEM)
        scope[SCOPE_INDEX] = context[SCOPE_INDEX] if context.key?(SCOPE_INDEX)
        scope
      end

      # What a finished run hands back: its declared outputs filled from its scope, or each step's output by its name.
      def result_of(workflow)
        outputs = workflow.definition_object.outputs
        scope = scope_for(workflow)
        return scope[SCOPE_STEPS].except(*workflow.context.to_h[CONTEXT_OUTER_STEPS].to_h.keys) if outputs.empty?

        clean(resolve(outputs, scope, workflow: workflow, step: nil), workflow: workflow, step: nil)
      end

      private

      def workflow_attributes(definition:, parent_step: nil, **)
        { definition: definition, parent_step_id: parent_step&.id }
      end

      def step_rows(definition:, not_before: nil, **)
        graph = SolidWorkflow::Definition.new(definition, action_kinds: action_kinds)
        problems = graph.problems
        raise SolidWorkflow::InvalidDefinition, problems.join(" ") if problems.any?

        graph.steps.map do |spec|
          incoming = graph.incoming(spec["id"])
          retry_config = (spec["retry"] || default_retry_config).to_h.stringify_keys
          row = {
            name: spec["id"], label: spec["name"], kind: spec["kind"], config: spec["config"] || {},
            incoming: incoming, depends_on: incoming.map { |edge| edge["from"] }.uniq,
            retry_config: retry_config, max_attempts: retry_config["max_attempts"] || SolidWorkflow.max_default_attempts,
            timeout_seconds: spec["timeout_seconds"], on_failure: spec["on_failure"] || SolidWorkflow::Definition::ON_FAILURE_STOP
          }
          row.merge!(status: :waiting, run_at: not_before) if not_before && not_before > Time.current && incoming.empty?
          row
        end
      end

      def wake_at_start(workflow, not_before)
        return unless not_before && not_before > Time.current

        workflow.steps.waiting.each { |step| SolidWorkflow::WakeJob.set(wait_until: not_before).perform_later(step.id) }
        workflow.record_event(SolidWorkflow::Events::Workflow::WAITING, until: not_before.iso8601)
      end
    end

    def run_step(step_name, workflow:, step:, input: {})
      spec = workflow.definition_object.step(step_name) || raise(SolidWorkflow::InvalidDefinition, "Step #{step_name} is not in the run's definition")
      config = spec["config"].to_h
      kept = step.kind == SolidWorkflow::Definition::KIND_FOR_EACH ? config.slice(*SolidWorkflow::Definition::BODY_KEYS) : {}
      filled = self.class.resolve(config.except(*kept.keys), self.class.scope_for(workflow), workflow: workflow, step: step)
      # Kept once, since a step that waits runs again on every wake and what it reads has already finished.
      step.update_column(:input, self.class.clean(filled, workflow: workflow, step: step)) if step.input.blank?

      result = self.class.stand_in(step, workflow: workflow) || run_kind(step, filled.merge(kept), workflow)
      case result
      when SolidWorkflow::Park then result
      when SolidWorkflow::Routed then SolidWorkflow::Routed.new(output: kept_output(result.output, workflow, step), route: result.route)
      else kept_output(result, workflow, step)
      end
    end

    private

    def kept_output(output, workflow, step) = self.class.clean(output.to_h.deep_stringify_keys, workflow: workflow, step: step)

    def run_kind(step, config, workflow)
      case step.kind
      when SolidWorkflow::Definition::KIND_BRANCH then branch(config)
      when SolidWorkflow::Definition::KIND_DELAY then delay(config, step)
      when SolidWorkflow::Definition::KIND_WAIT_FOR_EVENT then wait_for_event(config, step)
      when SolidWorkflow::Definition::KIND_FOR_EACH then for_each(config, step, workflow)
      when SolidWorkflow::Definition::KIND_JOIN then join(config, step, workflow)
      when SolidWorkflow::Definition::KIND_RUN_WORKFLOW then run_workflow(config, step, workflow)
      when SolidWorkflow::Definition::KIND_STOP then stop(config, step, workflow)
      else self.class.perform(step.kind, config, workflow: workflow, step: step)
      end
    end

    # Ends the run. Failed, the step fails with its reason and the run with it. Succeeded, every other step that has not
    # run yet is left as bypassed and anything they started is cancelled, so the run succeeds once the steps already
    # running finish.
    def stop(config, step, workflow)
      reason = config[SolidWorkflow::Definition::CONFIG_REASON].to_s.strip
      raise SolidWorkflow::Stopped, reason.presence || "Stopped." if config[SolidWorkflow::Definition::CONFIG_OUTCOME] == SolidWorkflow::Definition::STOP_FAILED

      workflow.stop_others!(step)
      { SolidWorkflow::Definition::OUTPUT_OUTCOME => SolidWorkflow::Definition::STOP_SUCCEEDED, SolidWorkflow::Definition::OUTPUT_REASON => reason }
    end

    # The first route whose condition holds, or the otherwise route. With neither, only edges without a route carry on.
    def branch(config)
      chosen = Array(config["routes"]).find { |route| SolidWorkflow::Condition.met?(route["when"]) }
      route = chosen ? chosen["route"] : config["otherwise"].presence
      SolidWorkflow::Routed.new(output: { SolidWorkflow::Definition::OUTPUT_ROUTE => route }, route: route)
    end

    def delay(config, step)
      resume_at = step.checkpoint.to_h[CHECKPOINT_RESUME_AT]&.then { |at| Time.zone.parse(at) } || remember_resume_at(step, config)
      return { SolidWorkflow::Definition::OUTPUT_WAITED_UNTIL => resume_at.iso8601 } if resume_at <= Time.current

      SolidWorkflow::Park.new(wake_at: resume_at)
    end

    def remember_resume_at(step, config)
      resume_at = resume_time(config)
      step.update_column(:checkpoint, step.checkpoint.to_h.merge(CHECKPOINT_RESUME_AT => resume_at.iso8601(6)))
      resume_at
    end

    def resume_time(config)
      seconds = SolidWorkflow::Definition::DELAY_UNITS.sum { |unit, size| config[unit].to_f * size }
      return Time.current + seconds.seconds if seconds.positive? || SolidWorkflow::Definition::DELAY_UNITS.keys.any? { |unit| config.key?(unit) }
      return Time.zone.parse(config["at"].to_s) || raise(ArgumentError, "Delay needs a moment it can read") if config.key?("at")

      zone = ActiveSupport::TimeZone[config["time_zone"].presence || Time.zone.name] || raise(ArgumentError, "Delay names an unknown time zone")
      hour, minute = config["until"].to_s.match(SolidWorkflow::Definition::TIME_OF_DAY)&.captures&.map(&:to_i) || raise(ArgumentError, "Delay needs a time of day such as 09:00")
      now = Time.current.in_time_zone(zone)
      today = now.change(hour: hour, min: minute, sec: 0)
      today > now ? today : today + 1.day
    end

    def wait_for_event(config, step)
      if step.signal_payload
        return SolidWorkflow::Routed.new(output: { SolidWorkflow::Definition::OUTPUT_OUTCOME => SolidWorkflow::Definition::ROUTE_RECEIVED,
                                                   SolidWorkflow::Definition::OUTPUT_EVENT => step.signal_payload },
                                         route: SolidWorkflow::Definition::ROUTE_RECEIVED)
      end

      deadline = deadline_of(step)
      if deadline && deadline <= Time.current
        return SolidWorkflow::Routed.new(output: { SolidWorkflow::Definition::OUTPUT_OUTCOME => SolidWorkflow::Definition::ROUTE_TIMED_OUT },
                                         route: SolidWorkflow::Definition::ROUTE_TIMED_OUT)
      end

      SolidWorkflow::Park.new(wake_at: deadline, signal_key: [ config["event"], config["key"].presence ].compact.join(":"))
    end

    # One run per item, at most concurrency at once. Each wakes the loop when it ends, and an item that fails ends the
    # loop with the rest cancelled.
    def for_each(config, step, workflow)
      items = config["items"]
      raise ArgumentError, "For each needs a list, and got #{items.class.name.downcase}" unless items.is_a?(Array)
      return { SolidWorkflow::Definition::OUTPUT_COUNT => 0, SolidWorkflow::Definition::OUTPUT_RESULTS => [] } if items.empty?

      children = step.children.to_a.index_by { |child| child.context[SCOPE_INDEX] }
      failed = children.values.find { |child| child.failed? || child.cancelled? }
      if failed
        workflow.cancel_children!(reason: "item_failed", by: nil, step_ids: [ step.id ])
        raise SolidWorkflow::SubWorkflowFailed, "Item #{failed.context[SCOPE_INDEX] + 1} of #{items.size} did not finish"
      end

      finished = children.values.count(&:succeeded?)
      if finished == items.size
        return { SolidWorkflow::Definition::OUTPUT_COUNT => items.size,
                 SolidWorkflow::Definition::OUTPUT_RESULTS => items.each_index.map { |index| children[index].result } }
      end

      give_up_on_time_limit!(step, workflow)
      start_items(config, step, workflow, items, children)
      SolidWorkflow::Park.new(wake_at: deadline_of(step))
    end

    def start_items(config, step, workflow, items, children)
      running = children.values.count(&:live?)
      slots = (config["concurrency"] || 1).to_i - running
      body = config.slice(*SolidWorkflow::Definition::BODY_KEYS)
      outer = self.class.scope_for(workflow)[SCOPE_STEPS]
      context = workflow.context.to_h.slice(SCOPE_INPUTS, SCOPE_TRIGGER)
      iteration = Array(workflow.context.to_h[CONTEXT_ITERATION])

      items.each_index.reject { |index| children.key?(index) }.first([ slots, 0 ].max).each do |index|
        self.class.start!(workflow.subject, definition: body, start_key: "#{step.id}:#{index}", parent_step: step,
                                            context: context.merge(CONTEXT_OUTER_STEPS => outer, SCOPE_ITEM => items[index], SCOPE_INDEX => index,
                                                                   CONTEXT_ITERATION => iteration + [ index ]))
      end
    end

    def join(config, step, workflow)
      step_map = workflow.steps.to_a.index_by(&:name)
      sources = step.live_sources(step_map)
      if config["mode"] == SolidWorkflow::Definition::JOIN_FIRST
        first = sources.min_by { |source| source.completed_at || Time.current }
        return { SolidWorkflow::Definition::OUTPUT_FIRST => first&.label, SolidWorkflow::Definition::OUTPUT_OUTPUT => first&.output }
      end

      { SolidWorkflow::Definition::OUTPUT_STEPS => sources.to_h { |source| [ source.label, source.output ] } }
    end

    def run_workflow(config, step, workflow)
      child = step.children.first || self.class.start_sub_workflow(config, workflow: workflow, step: step)
      return child.result.to_h if child.succeeded?
      raise SolidWorkflow::SubWorkflowFailed, "The workflow it ran #{child.state}" if child.failed? || child.cancelled?

      give_up_on_time_limit!(step, workflow)
      SolidWorkflow::Park.new(wake_at: deadline_of(step))
    end

    def give_up_on_time_limit!(step, workflow)
      deadline = deadline_of(step)
      return unless deadline && deadline <= Time.current

      workflow.cancel_children!(reason: "time_limit", by: nil, step_ids: [ step.id ])
      raise SolidWorkflow::TimeLimitReached, "Ran past its time limit of #{step.timeout_seconds} seconds"
    end

    def deadline_of(step)
      return unless step.timeout_seconds && step.first_started_at

      step.first_started_at + step.timeout_seconds.seconds
    end
  end
end
