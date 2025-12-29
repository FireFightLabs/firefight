module WorkflowStep::Dependencies
  extend ActiveSupport::Concern

  def ready_to_run?(all_steps)
    return false unless pending?
    return false if run_at && run_at > Time.current

    depends_on.all? do |dep_name|
      dep_step = all_steps.find { |s| s.name == dep_name }
      dep_step && (dep_step.succeeded? || dep_step.skipped?)
    end
  end

  def populate_input!(all_steps)
    input_data = {}
    depends_on.each do |dep_name|
      dep_step = all_steps.find { |s| s.name == dep_name }
      input_data[dep_name] = dep_step.output if dep_step
    end
  update!(input: input_data) if input_data.any?
  end
end
