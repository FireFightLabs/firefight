# frozen_string_literal: true

# IdempotentSteps - Reusable patterns for making workflow steps idempotent
#
# Provides helper methods to reduce boilerplate when implementing idempotent steps.
# Steps using these helpers are safe to retry without side effects.
#
# Usage:
#   class MyWorkflow < Workflows::Base
#     include IdempotentSteps
#
#     def create_channel(workflow:, step:, input:)
#       incident = workflow.subject
#
#       idempotent_field(incident, :slack_channel_id) do
#         SlackClient.create_channel("inc-#{incident.id}")
#       end
#     end
#   end
#
module IdempotentSteps
  # Check if a field has a value, return it or execute block and store result
  #
  # This is useful for steps that create external resources and store an identifier.
  # If the field already has a value (from a previous execution), return it immediately.
  # Otherwise, execute the block and store the result.
  #
  # @param record [ActiveRecord::Base] The record to check (usually workflow.subject)
  # @param field [Symbol] The field name to check
  # @yield Block that creates/fetches the value
  # @return [Hash] Hash with field name as key
  #
  # @example Create Slack channel
  #   idempotent_field(incident, :slack_channel_id) do
  #     SlackClient.create_channel("inc-#{incident.id}")
  #   end
  #   # First run: Creates channel, stores ID, returns { slack_channel_id: "C123" }
  #   # Retry: Returns existing ID immediately
  #
  def idempotent_field(record, field, &block)
    value = record.public_send(field)

    if value.present?
      Rails.logger.info(
        :idempotent_field_cache_hit,
        record_type: record.class.name,
        record_id: record.id,
        field: field
      )
      return { field => value }
    end

    result = block.call
    record.update!(field => result)

    Rails.logger.info(
      :idempotent_field_created,
      record_type: record.class.name,
      record_id: record.id,
      field: field
    )

    { field => result }
  end

  # Find existing resource or create it
  #
  # Useful for resources that might already exist in an external system.
  # Tries to find the resource first (DB, then external system), creates if not found.
  #
  # @param local_check [Proc] Check local database first
  # @param external_check [Proc] Check external system (optional)
  # @param create [Proc] Create the resource
  # @return [Object] The found or created resource
  #
  # @example Find or create Slack channel
  #   find_or_create(
  #     local_check: -> { incident.slack_channel_id },
  #     external_check: -> { SlackClient.find_channel_by_name("inc-#{incident.id}") },
  #     create: -> { SlackClient.create_channel("inc-#{incident.id}") }
  #   )
  #
  def find_or_create(local_check:, external_check: nil, create:)
    # Check local DB first
    local = local_check.call
    return local if local.present?

    # Check external system if provided
    if external_check
      external = external_check.call
      return external if external.present?
    end

    # Create if not found
    create.call
  end

  # Execute block only if condition is true, otherwise skip
  #
  # Useful for conditional step logic that should mark the step as skipped
  # rather than failed when the condition isn't met.
  #
  # @param condition [Boolean] Whether to execute the block
  # @param skip_reason [String] Reason for skipping
  # @yield Block to execute if condition is true
  # @return [Hash] Result from block or skip indicator
  #
  # @example Only send premium welcome for premium users
  #   conditional_step(
  #     user.premium?,
  #     skip_reason: "User is not on premium plan"
  #   ) do
  #     PremiumMailer.welcome(user).deliver_now
  #     { email_sent: true }
  #   end
  #
  def conditional_step(condition, skip_reason:, &block)
    unless condition
      Rails.logger.info(:conditional_step_skipped, reason: skip_reason)
      return { skipped: true, reason: skip_reason }
    end

    block.call
  end

  # Retry block with exponential backoff for transient errors
  #
  # Useful for handling temporary failures (rate limits, network issues)
  # within a step's execution.
  #
  # @param max_attempts [Integer] Maximum retry attempts
  # @param backoff_base [Integer] Base for exponential backoff (seconds)
  # @param rescue_classes [Array<Class>] Error classes to retry
  # @yield Block to execute with retries
  #
  # @example Handle Slack rate limits
  #   with_retry(max_attempts: 3, rescue_classes: [Slack::Web::Api::Errors::TooManyRequestsError]) do
  #     SlackClient.post_message(channel, text)
  #   end
  #
  def with_retry(max_attempts: 3, backoff_base: 2, rescue_classes: [ StandardError ], &block)
    attempt = 0

    begin
      attempt += 1
      block.call
    rescue *rescue_classes => e
      if attempt < max_attempts
        sleep_time = backoff_base**attempt
        Rails.logger.warn(
          :step_retry,
          attempt: attempt,
          max_attempts: max_attempts,
          sleep_seconds: sleep_time,
          error: e.message
        )
        sleep(sleep_time)
        retry
      else
        raise
      end
    end
  end
end
