module SolidWorkflow
  class Step < Record
    module Dependencies
      extend ActiveSupport::Concern

      def ready_to_run?(all_steps_or_map)
        return false unless pending?
        return false if run_at && run_at > Time.current

        step_map = all_steps_or_map.is_a?(Hash) ? all_steps_or_map : all_steps_or_map.index_by(&:name)

        depends_on.all? do |dep_name|
          dep_step = step_map[dep_name]
          dep_step && (dep_step.succeeded? || dep_step.skipped?)
        end
      end

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
            input_data[dep_name] = dep_step.output
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

      def populate_input!(all_steps)
        populate_input_data(all_steps)
        save! if changed?
      end
    end
  end
end
