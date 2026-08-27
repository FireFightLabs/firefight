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

    def checkpointed(step, key = :result, &block)
      cached = step.checkpoint&.dig(key.to_s)
      return cached if cached.present?

      result = yield
      merged = (step.checkpoint || {}).merge(key.to_s => result)
      step.update_column(:checkpoint, merged)
      result
    end
  end
end
