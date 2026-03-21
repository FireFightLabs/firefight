module FirefightAi
  class PostmortemGenerationJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    discard_on ActiveRecord::RecordNotFound

    def perform(incident_id, generated_by_id)
      incident = Incident.find(incident_id)
      member = WorkspaceMembership.find(generated_by_id)
      return if incident.postmortem.present?

      generator = PostmortemGenerator.new(incident.workspace)
      generator.generate(incident, generated_by: member)
      generator.post_message(incident)
    end
  end
end
