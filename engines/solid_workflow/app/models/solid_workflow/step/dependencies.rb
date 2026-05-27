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

      # Cascades transitive parent inputs forward so a late step has the
      # full chain of upstream parameters available without re-querying the
      # DB — supports replay/idempotency even if the source records mutate
      # later. Capped so a runaway chain becomes observable instead of
      # silently bloating the input column.
      MAX_INPUT_BYTES = 64_000

      def populate_input_data(all_steps, step_map: nil)
        input_data = {}
        step_map ||= all_steps.index_by(&:name)

        depends_on.each do |dep_name|
          dep_step = step_map[dep_name]
          next unless dep_step

          input_data[dep_name] = dep_step.output
          input_data.merge!(dep_step.input) if dep_step.input.present?
        end

        warn_if_input_too_large(input_data)
        self.input = input_data if input_data.any?
      end

      def warn_if_input_too_large(input_data)
        size = input_data.to_json.bytesize
        return if size <= MAX_INPUT_BYTES

        Rails.logger.warn({
          event:       "workflow.step.input_size_exceeded",
          workflow_id: workflow_id,
          step_id:     id,
          step_name:   name,
          size_bytes:  size,
          cap_bytes:   MAX_INPUT_BYTES
        })
      end

      def populate_input!(all_steps)
        populate_input_data(all_steps)
        save! if changed?
      end
    end
  end
end
