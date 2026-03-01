module SolidWorkflow
  module IdempotentSteps
    def idempotent_field(record, field, &block)
      value = record.public_send(field)

      if value.present?
        Rails.logger.info({
          event: "workflow.idempotent_field.cache_hit",
          record_type: record.class.name,
          record_id: record.id,
          field: field
        })
        return { field => value }
      end

      result = block.call
      record.update!(field => result)

      Rails.logger.info({
        event: "workflow.idempotent_field.created",
        record_type: record.class.name,
        record_id: record.id,
        field: field
      })

      { field => result }
    end

    def find_or_create(local_check:, external_check: nil, create:)
      local = local_check.call
      return local if local.present?

      if external_check
        external = external_check.call
        return external if external.present?
      end

      create.call
    end

    def conditional_step(condition, skip_reason:, &block)
      unless condition
        Rails.logger.info({ event: "workflow.step.skipped", reason: skip_reason })
        return { skipped: true, reason: skip_reason }
      end

      block.call
    end

    def with_retry(max_attempts: 3, backoff_base: 2, rescue_classes: [ StandardError ], &block)
      attempt = 0

      begin
        attempt += 1
        block.call
      rescue *rescue_classes => e
        if attempt < max_attempts
          sleep_time = backoff_base**attempt
          Rails.logger.warn({
            event: "workflow.step.retry",
            attempt: attempt,
            max_attempts: max_attempts,
            sleep_seconds: sleep_time,
            error: e.message
          })
          sleep(sleep_time)
          retry
        else
          raise
        end
      end
    end
  end
end
