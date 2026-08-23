module FirefightAi
  class PostmortemGenerationJob < ApplicationJob
    queue_as :default

    # Transient: retry with backoff, then notify the requester so they aren't
    # left with a silent "generating..." ephemeral that never resolves.
    retry_on RubyLLM::RateLimitError,
             RubyLLM::ServerError,
             RubyLLM::ServiceUnavailableError,
             RubyLLM::OverloadedError,
             Net::ReadTimeout,
             Faraday::TimeoutError,
             wait: :polynomially_longer, attempts: 3 do |job, error|
      job.cleanup_in_progress!
      job.notify_failure(error, terminal: false)
    end

    # Terminal: retrying produces the same outcome (auth, payment, context
    # length, schema). Don't burn tokens on retry. Notify and stop.
    discard_on RubyLLM::ContextLengthExceededError,
               RubyLLM::BadRequestError,
               RubyLLM::UnauthorizedError,
               RubyLLM::ForbiddenError,
               RubyLLM::PaymentRequiredError,
               RubyLLM::ModelNotFoundError do |job, error|
      job.record_failure(error)
      job.notify_failure(error, terminal: true)
    end

    discard_on ActiveRecord::RecordNotFound

    def perform(incident_id, generated_by_id)
      incident = Incident.find(incident_id)
      member = WorkspaceMembership.find(generated_by_id)
      return unless incident.postmortem&.generating?

      unless Entitlements.allows?(incident.workspace, Entitlements::AI)
        incident.postmortem.mark_generation_failed!(Entitlements::Result)
        Rails.logger.info({ event: "postmortem_generation.entitlement_blocked", incident_id: incident_id, workspace_id: incident.workspace_id })
        return
      end

      generator = PostmortemGenerator.new(incident.workspace)
      generator.generate(incident, generated_by: member)
      generator.post_message(incident)
    end

    # The placeholder stays, marked failed, so the page can say what happened
    # and offer a retry instead of showing an empty incident.
    def record_failure(error)
      incident_id, = arguments
      postmortem = Incident.find_by(id: incident_id)&.postmortem
      postmortem.mark_generation_failed!(error) if postmortem&.generating?
    end

    def notify_failure(error, terminal:)
      incident_id, member_id = arguments
      incident = Incident.find_by(id: incident_id)
      member = WorkspaceMembership.find_by(id: member_id)
      return unless incident && member && incident.channel_id && member.platform_user_id

      reason = error.class.name.demodulize
      text = if terminal
        ":warning: Postmortem generation for #{incident.identifier} failed (reason: #{reason}) and won't retry automatically. Try again from the incident page or with `/firefight postmortem`."
      else
        ":warning: Postmortem generation for #{incident.identifier} failed after retries. Try again from the incident page or with `/firefight postmortem`."
      end

      incident.workspace.adapter.post_ephemeral(
        channel_id: incident.channel_id,
        user_id: member.platform_user_id,
        text: text
      )
    rescue StandardError => e
      Rails.logger.error({
        event: "postmortem_generation.notify_failure_failed",
        incident_id: incident_id,
        error_class: e.class.name,
        error: e.message
      })
    end
  end
end
