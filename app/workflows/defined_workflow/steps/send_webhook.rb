# Sends a signed POST with the run's data through one of the workspace's outbound webhooks, as the same delivery an
# incident event gets (Webhooks::DeliveryService): signed with the webhook's secret, through the guard that keeps it off
# private networks, kept on the webhook's deliveries and counted towards turning off a webhook that keeps failing. It is
# sent by the step and its answer waited for, so a failure takes the step's error route. It is authorized as changing
# the webhook (webhooks.update), approval rules can hold it, and it cannot be taken back once sent, so it has no undo.
class DefinedWorkflow::Steps::SendWebhook < DefinedWorkflow::Steps::CallTool
  kind "send_webhook"
  label "Send webhook"
  group GROUP_HTTP

  KEY_WEBHOOK = "webhook".freeze
  KEY_EVENT = "event".freeze
  KEY_PAYLOAD = "payload".freeze
  EVENT_PREFIX = "workflow.".freeze
  EVENT_FORMAT = /\A[a-z0-9_.]+\z/
  ACTION = Ability::Action.system_key(Ability::Action::RESOURCE_WEBHOOKS, Ability::Action::ACTION_UPDATE)
  OUTPUT_DELIVERED = "delivered".freeze
  OUTPUT_STATUS = "status".freeze
  OUTPUT_DELIVERY = "delivery_id".freeze

  config_help "webhook (the name of one of the workspace's outbound webhooks), event (its event type, such as workflow.release, " \
              "workflow.<the workflow's slug> by default), payload (what it sends as data, usually a reference). Outputs delivered, " \
              "status and delivery_id. A delivery that fails fails the step."

  class << self
    def changes?(_config, _workspace) = true

    def checks?(_config, _workspace) = false

    def undoable?(_config, _workspace) = false

    def output_fields(_config) = [ OUTPUT_DELIVERED, OUTPUT_STATUS, OUTPUT_DELIVERY ]

    def problems(step, workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = []
      if config[KEY_WEBHOOK].to_s.strip.empty?
        found << "#{named} needs the outbound webhook it sends through."
      elsif !workspace.webhooks.exists?(name: config[KEY_WEBHOOK].to_s)
        found << "#{named} sends through #{config[KEY_WEBHOOK]}, which is not one of this workspace's outbound webhooks."
      end
      event = config[KEY_EVENT].to_s
      found << "#{named} names its event in lowercase letters, numbers, dots and underscores." unless event.empty? || event.match?(EVENT_FORMAT)
      found
    end

    def reach(_config, workspace)
      action = Ability::Action.lookup(ACTION, workspace)
      action ? [ DefinedWorkflow::Reach::Needed.of_action(action) ] : []
    end

    def describe(config, _workspace) = "Through #{config[KEY_WEBHOOK]}: #{config[KEY_EVENT].presence || 'the workflow event'}".truncate(200)
  end

  def tool_name = label

  def arguments = { KEY_WEBHOOK => @config[KEY_WEBHOOK].to_s, KEY_EVENT => event }

  def frozen = nil

  def read_first(*, **) = nil

  private

  def label = self.class.label

  def named = self.class.describe(@config, workspace)

  def event = @config[KEY_EVENT].presence || "#{EVENT_PREFIX}#{@run.workflow.slug}"

  def call(approval_id)
    webhook = workspace.webhooks.find_by(name: @config[KEY_WEBHOOK].to_s)
    raise Refused, "No outbound webhook here is called #{@config[KEY_WEBHOOK]}." unless webhook
    raise Refused, "#{webhook.name} is turned off, so nothing was sent." unless webhook.active?

    agent_run = Workflow::AgentRun.new(run: @run, record: record, approval_id: approval_id)
    delivery = agent_run.tool_call(action_key: ACTION, params: arguments) do |authorization|
      sent = deliver(webhook)
      authorization.answer_failed!(sent.error_message) unless sent.succeeded?
      sent
    end.value
    raise Failed, "#{webhook.name} did not take it: #{delivery.error_message || "it answered #{delivery.response_code}"}." unless delivery.succeeded?

    { OUTPUT_DELIVERED => true, OUTPUT_STATUS => delivery.response_code, OUTPUT_DELIVERY => delivery.id }
  rescue AbilityGateway::PendingApproval => pending
    wait_for(pending.approval)
  rescue AbilityGateway::Denied
    raise Refused, agent_run.refusal(ACTION)
  end

  # The delivery, signed and sent now, in the same envelope an incident event's has, with the step's payload as its data.
  def deliver(webhook)
    delivery = webhook.webhook_deliveries.create!(workflow_run: @run, event_type: event, sent_by_caller: true, signed_payload: "{}")
    delivery.update!(signed_payload: envelope(delivery).to_json)
    Webhooks::DeliveryService.deliver(delivery)
    delivery.reload
  end

  def envelope(delivery)
    {
      "id" => delivery.id, "version" => Webhooks::DeliveryService::PAYLOAD_VERSION, "event_type" => event, "workspace_id" => workspace.id,
      "occurred_at" => Time.current.utc.iso8601, "data" => { "workflow" => { "name" => @run.workflow.name, "slug" => @run.workflow.slug },
                                                             "run_id" => @run.id, "payload" => @config[KEY_PAYLOAD] }
    }
  end
end
