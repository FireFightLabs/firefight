# Halon sorts what it is given into one of the routes the step names, each an edge on the canvas, such as a page that
# is noise, a real outage or something to watch. It answers with one structured call, as Ask Halon does, and an answer
# that names no route takes the otherwise route, so the run always goes somewhere. It reads only what it is given.
class DefinedWorkflow::Steps::Classify < DefinedWorkflow::Steps::Base
  kind "classify"
  label "Classify"
  group GROUP_HALON

  KEY_DATA = "data".freeze
  KEY_ROUTES = "routes".freeze
  KEY_GUIDANCE = "guidance".freeze
  KEY_OTHERWISE = "otherwise".freeze
  OUTPUT_ROUTE = "route".freeze
  ROUTE_LIMIT = 10
  DEFAULT_OTHERWISE = "other".freeze
  HANDED_OFF = "halon".freeze

  config_help "data (what to sort, usually a reference such as {{trigger.alert}}), routes (up to #{ROUTE_LIMIT} route names, lowercase " \
              "with underscores, each an edge out of the step), guidance (how to tell them apart, optional), otherwise (the route taken when " \
              "none fits, #{DEFAULT_OTHERWISE} by default). Outputs route and summary, and takes the route."

  class << self
    def routes_of(config) = Array(config[KEY_ROUTES]).map(&:to_s).compact_blank.uniq

    def otherwise(config) = config[KEY_OTHERWISE].to_s.strip.presence || DEFAULT_OTHERWISE

    # Every route an edge out of it may carry, the otherwise route last.
    def all_routes(config) = [ *routes_of(config), otherwise(config) ].uniq

    def output_fields(_config) = [ OUTPUT_ROUTE, Workflow::HalonStep::SUMMARY ]

    def problems(step, _workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      routes = routes_of(config)
      found = []
      found << "#{named} needs what Halon sorts." if config[KEY_DATA].to_s.strip.empty?
      found << "#{named} needs at least two routes to sort into." if routes.size < 2
      found << "#{named} sorts into at most #{ROUTE_LIMIT} routes." if routes.size > ROUTE_LIMIT
      if all_routes(config).any? { |route| !route.match?(SolidWorkflow::Definition::STEP_NAME) }
        found << "Each route of #{named} needs a name of lowercase letters, numbers and underscores."
      end
      found
    end

    def describe(config, _workspace) = "Into #{all_routes(config).join(', ')}".truncate(200)
  end

  def perform
    asked = { DefinedWorkflow::Steps::AskHalon::KEY_QUESTION => question, DefinedWorkflow::Steps::AskHalon::KEY_DATA => @config[KEY_DATA],
              DefinedWorkflow::Steps::AskHalon::KEY_FIELDS => [ { DefinedWorkflow::Steps::AskHalon::FIELD_NAME => OUTPUT_ROUTE,
                                                                   DefinedWorkflow::Steps::AskHalon::FIELD_DESCRIPTION => route_words } ] }
    answer = await(HANDED_OFF) { |name| WorkflowHalonStepJob.perform_later(@run.id, record&.id, @step.id, DefinedWorkflow::Steps::AskHalon.kind, asked, name) }
    return answer if answer.is_a?(SolidWorkflow::Park)
    raise Failed, answer[Workflow::HalonStep::KEY_ERROR] if answer[Workflow::HalonStep::KEY_ERROR]

    chosen = answer[OUTPUT_ROUTE].to_s.strip.downcase
    route = self.class.routes_of(@config).include?(chosen) ? chosen : self.class.otherwise(@config)
    SolidWorkflow::Routed.new(output: { OUTPUT_ROUTE => route, Workflow::HalonStep::SUMMARY => answer[Workflow::HalonStep::SUMMARY] }, route: route)
  end

  private

  def question
    [ "Sort what you are given into exactly one of these: #{self.class.routes_of(@config).join(', ')}.",
      @config[KEY_GUIDANCE].to_s.strip.presence&.then { |words| "How to tell them apart: #{words}" },
      "When none fits, answer #{self.class.otherwise(@config)}. Say in the summary why." ].compact.join("\n\n")
  end

  def route_words = "Exactly one of: #{self.class.all_routes(@config).join(', ')}"
end
