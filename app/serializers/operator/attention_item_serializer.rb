module Operator
  # One Needs attention item, with the path to its record.
  class AttentionItemSerializer < BaseSerializer
    object_as :item

    KIND_UNION = Operator::Attention::KINDS.map(&:inspect).join(" | ")
    TONE_UNION = Operator::IncidentProcess::TONES.map(&:inspect).join(" | ")

    type :string
    def key = item.key

    type KIND_UNION
    def kind = item.kind

    type TONE_UNION
    def tone = item.tone

    type :string
    def title = item.title

    type :string
    def subject = item.subject

    type :string
    def place = item.place

    type :string, optional: true
    def detail = item.detail

    type :string
    def at = item.at.utc.iso8601

    # Jobs links go to Flightdeck, which is not an Inertia page, so the page loads them in full.
    type :string, optional: true
    def href
      routes = Rails.application.routes.url_helpers
      case item.target
      when Operator::Attention::TARGET_WORKFLOW then routes.operator_workflow_path(item.target_id)
      when Operator::Attention::TARGET_INCIDENT then routes.operator_incident_path(item.target_id)
      when Operator::Attention::TARGET_RUN then routes.operator_halon_run_path(item.target_id)
      when Operator::Attention::TARGET_FAILED_JOBS then "#{routes.operator_jobs_path}/jobs?state=failed"
      when Operator::Attention::TARGET_QUEUES then "#{routes.operator_jobs_path}/queues"
      end
    end

    type :boolean
    def external = [ Operator::Attention::TARGET_FAILED_JOBS, Operator::Attention::TARGET_QUEUES ].include?(item.target)
  end
end
