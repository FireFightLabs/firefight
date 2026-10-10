# A fresh reading of an unattended rule's metric for its resource, made as Halon through the gateway like any read in a
# run, so it is in the activity log. Its average over the rule's minutes decides whether the rule lets Halon act. A read
# never waits for an approval, since nothing could pick it up again once one was given.
class Ability::UnattendedRule::Reading
  # Why no reading could be made, in words the incident is told.
  class Unread < StandardError; end

  # value is the highest average among the metric's series, such as one per container, so a single bad one counts.
  Result = Data.define(:rule, :value, :series) do
    def above? = value > rule.threshold

    def words
      on = " on #{series}" if series.present?
      "Halon read #{rule.resource.name} just now. The average of its #{rule.metric_label} over the last #{rule.minutes} minutes was " \
        "#{shown}#{on}, #{above? ? 'above' : 'not above'} #{rule.shown_threshold}."
    end

    def shown
      rounded = Integrations::Telemetry.round(value)
      rounded == rounded.to_i ? rounded.to_i : rounded
    end
  end

  def initialize(rule, incident: nil)
    @rule = rule
    @incident = incident
    @workspace = rule.workspace
    @principal = SystemAgent.investigator
  end

  def read!
    call = Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::METRICS, asked,
                                              Integrations::Capabilities.callable(@workspace, Integrations::Capabilities::METRICS, @principal),
                                              principal: @principal)
    answer = run(call)
    answer = run(call.fallback) if call.fallback && !Integrations::Capabilities.definitive?(answer)
    result_from(answer)
  rescue Integrations::Capabilities::Unroutable => error
    raise Unread, "Halon could not read the #{@rule.metric_label} of #{@rule.resource.name}: #{error.message}"
  rescue AbilityGateway::Denied
    raise Unread, "#{@rule.investigator_name} may not read #{@rule.resource.name}'s metrics."
  rescue Integrations::Error => error
    raise Unread, "#{@rule.resource.name}'s metrics did not answer: #{error.message.truncate(200)}"
  end

  private

  def asked
    { Integrations::Capabilities::RESOURCE_ARG => @rule.resource_id, "metrics" => [ @rule.metric ], "minutes" => @rule.minutes }
  end

  def run(call)
    Chat::ToolCall.run!(
      workspace: @workspace, principal: @principal, action_key: call.tool.action_key, scope: call.scope, params: call.arguments,
      context: { source: AbilityGateway::SOURCE_INVESTIGATION, incident_id: @incident&.id, triggered_by_label: "Checking the unattended rule: #{@rule.sentence}" }.compact,
      holdable: false
    ) do |authorization|
      answer = call.present_result(call.tool.integration.executor.call(tool: call.tool, environment_row: call.environment_row, arguments: call.arguments))
      authorization.answer_failed!(Integrations::Capabilities::Answers.text(answer)) if answer["isError"] == true
      answer
    end
  end

  def result_from(answer)
    raise Unread, "#{@rule.resource.name}'s #{@rule.metric_label} could not be read: #{Integrations::Capabilities::Answers.text(answer).truncate(200)}" if answer["isError"] == true

    averages = charts(answer).flat_map do |chart|
      Array(chart["series"]).filter_map do |series|
        values = Array(series["points"]).map { |_at, value| value }.compact.map(&:to_f)
        [ series["label"].to_s, values.sum / values.size ] if values.any?
      end
    end
    raise Unread, "#{@rule.resource.name} has no #{@rule.metric_label} in the last #{@rule.minutes} minutes, so nothing shows it is above #{@rule.shown_threshold}." if averages.empty?

    series, value = averages.max_by(&:last)
    Result.new(rule: @rule, value: value, series: (series if averages.size > 1))
  end

  def charts(answer) = Array(answer.dig(Integrations::Telemetry::STRUCTURED, Integrations::Telemetry::CHARTS))
end
