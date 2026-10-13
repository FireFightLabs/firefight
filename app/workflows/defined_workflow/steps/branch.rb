# If and else on the run's data, or a switch of several routes, run by the engine. Steps on a route not taken are
# bypassed. It only reads the run's own data.
class DefinedWorkflow::Steps::Branch < DefinedWorkflow::Steps::Base
  kind DefinedWorkflow::KIND_BRANCH
  label "Branch"
  group GROUP_CONTROL
  config_help "routes (each {route, when: {left, operator, right}}, operators such as equals, contains, greater_than, combined with all, any and not), " \
              "otherwise (the route when none holds). Connect each route's next step with that route."

  def self.engine? = true

  def self.problems(_step, _workspace) = []

  def self.output_fields(_config) = SolidWorkflow::Definition::OUTPUT_FIELDS.fetch(DefinedWorkflow::KIND_BRANCH)

  def self.describe(config, _workspace)
    routes = Array(config["routes"]).filter_map { |route| route["route"] if route.is_a?(Hash) }
    [ *routes, config["otherwise"].presence ].compact.join(" or ")
  end
end
