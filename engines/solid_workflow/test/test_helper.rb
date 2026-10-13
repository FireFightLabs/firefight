require_relative "../../../test/test_helper"

# A host for the interpreter's tests: echo hands back its config, fail raises, and references are filled from the scope.
class TestDefinedWorkflow < SolidWorkflow::Interpreter
  REFERENCE = /\{\{\s*([a-z0-9_.]+)\s*\}\}/

  class << self
    attr_accessor :held, :sub_definition, :observed, :stand_ins

    def action_kinds = %w[echo fail slow]

    def stand_in(step, workflow:) = stand_ins.to_h[step.name]

    def runnable?(_workflow) = !held

    def observe(workflow, event)
      (self.observed ||= []) << [ workflow.id, event.event_type, event.step&.label ]
    end

    def resolve(value, scope, workflow:, step:)
      case value
      when String
        whole = value.match(/\A#{REFERENCE}\z/)
        whole ? dig(scope, whole[1]) : value.gsub(REFERENCE) { dig(scope, Regexp.last_match(1)).to_s }
      when Hash then value.transform_values { |inner| resolve(inner, scope, workflow:, step:) }
      when Array then value.map { |inner| resolve(inner, scope, workflow:, step:) }
      else value
      end
    end

    def perform(kind, config, workflow:, step:)
      case kind
      when "echo" then config
      when "fail" then raise(config["terminal"] ? ArgumentError : RuntimeError, config["message"] || "it failed")
      when "slow" then config
      end
    end

    def start_sub_workflow(config, workflow:, step:)
      start!(workflow.subject, definition: sub_definition, context: { "inputs" => config["inputs"] }, start_key: "sub:#{step.id}", parent_step: step)
    end

    private

    def dig(scope, path) = path.split(".").reduce(scope) { |found, key| found.is_a?(Hash) ? found[key] : (found.is_a?(Array) ? found[key.to_i] : nil) }
  end
end

module DefinedWorkflowTestHelper
  include ActiveJob::TestHelper

  def setup_defined_workflow
    TestDefinedWorkflow.held = false
    TestDefinedWorkflow.observed = []
    TestDefinedWorkflow.sub_definition = nil
    TestDefinedWorkflow.stand_ins = nil
    @subject = User.create!(name: "Defined Workflow User", email: "dw-#{SecureRandom.hex(4)}@example.com")
  end

  def step(id, kind, config = {}, **extra) = { "id" => id, "name" => id, "kind" => kind, "config" => config }.merge(extra.stringify_keys)

  def edge(from, to, route = nil) = { "from" => from, "to" => to, "route" => route }.compact

  def run_definition(definition, **options)
    workflow = nil
    perform_enqueued_jobs { workflow = TestDefinedWorkflow.start!(@subject, definition: definition, **options) }
    workflow.reload
  end

  def status_of(workflow, id) = workflow.steps.find_by!(name: id).status

  def output_of(workflow, id) = workflow.steps.find_by!(name: id).output
end
