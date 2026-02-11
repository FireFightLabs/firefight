module WorkflowStep::Dependencies
  extend ActiveSupport::Concern

  def ready_to_run?(all_steps_or_map)
    return false unless pending?
    return false if run_at && run_at > Time.current

    # Support both array (legacy) and hash map (optimized) lookups
    step_map = all_steps_or_map.is_a?(Hash) ? all_steps_or_map : all_steps_or_map.index_by(&:name)

    depends_on.all? do |dep_name|
      dep_step = step_map[dep_name]
      dep_step && (dep_step.succeeded? || dep_step.skipped?)
    end
  end

  # Populate input data without saving (for batch updates)
  def populate_input_data(all_steps, step_map: nil)
    input_data = {}
    step_map ||= all_steps.index_by(&:name)

    depends_on.each do |dep_name|
      dep_step = step_map[dep_name]

      Rails.logger.info({
        event: "workflow.step.populate_input.debug",
        step_name: name,
        dep_name: dep_name,
        dep_step_found: !!dep_step,
        dep_step_output: dep_step&.output,
        dep_step_status: dep_step&.status
      })

      if dep_step
        # Store the dependency's output under its name
        input_data[dep_name] = dep_step.output

        # Also merge in all of the dependency's input data to propagate data through the chain
        # This allows downstream steps to access data from any upstream step, not just direct dependencies
        input_data.merge!(dep_step.input) if dep_step.input.present?
      end
    end

    Rails.logger.info({
      event: "workflow.step.populate_input.result",
      step_name: name,
      input_data: input_data
    })

    self.input = input_data if input_data.any?
  end

  # Legacy method for backward compatibility
  def populate_input!(all_steps)
    populate_input_data(all_steps)
    save! if changed?
  end
end
