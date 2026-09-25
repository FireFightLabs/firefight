module Operator
  # One Find match, with the path that opens it.
  class FindMatchSerializer < BaseSerializer
    object_as :match

    KIND_UNION = Operator::Finder::KINDS.map(&:inspect).join(" | ")

    def self.path_for(match)
      routes = Rails.application.routes.url_helpers
      case match.kind
      when Operator::Finder::KIND_INCIDENT then routes.operator_incident_path(match.id)
      when Operator::Finder::KIND_RUN then routes.operator_halon_run_path(match.id, **span_param(match))
      when Operator::Finder::KIND_CHAT then routes.operator_halon_chat_path(match.id, **span_param(match))
      when Operator::Finder::KIND_WORKFLOW then routes.operator_workflow_path(match.id)
      end
    end

    def self.span_param(match) = match.span ? { Operator::Trace::SPAN_PARAM => match.span } : {}

    type KIND_UNION
    def kind = match.kind

    type :string
    def id = match.id

    type :string
    def label = match.label

    type :string
    def place = match.place

    type :string, optional: true
    def via = match.via

    type :string
    def href = self.class.path_for(match)
  end
end
