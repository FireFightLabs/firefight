# Sends one HTTP request through the guard outbound webhooks use, which keeps it off private networks. A GET or HEAD only
# reads (http_requests.read), any other method changes something (http_requests.create), so it needs its undo, approval
# rules can hold it, a freeze stops it and a test run only shows it. Credentials come from a connection the step names,
# added by Firefight for that connection's own hosts and never kept in the step.
class DefinedWorkflow::Steps::HttpRequest < DefinedWorkflow::Steps::CallTool
  kind "http_request"
  label "HTTP request"
  group GROUP_HTTP

  KEY_METHOD = "method".freeze
  KEY_URL = "url".freeze
  KEY_HEADERS = "headers".freeze
  KEY_BODY = "body".freeze
  KEY_CONNECTION = "connection".freeze
  METHODS = Workflow::HttpCall::METHODS
  READS = Workflow::HttpCall::READS
  OUTPUT_STATUS = "status".freeze
  OUTPUT_BODY = "body".freeze
  OUTPUT_CONTENT_TYPE = "content_type".freeze
  HEADER_LINE = /\A([A-Za-z0-9-]+):\s*(.+)\z/
  BODY_KEPT = 100_000

  config_help "method (#{METHODS.join(', ')}, GET by default), url, headers (lines of Name: value, never a secret), body (for a change, " \
              "text or a reference), connection (a connection's slug, whose credentials go with it to that connection's own hosts), undo " \
              "(for anything but GET and HEAD). Outputs status, content_type, body and data (the body read as JSON). An answer of 400 or " \
              "more fails the step."

  class << self
    def method_of(config) = (config[KEY_METHOD].presence || READS.first).to_s.upcase

    def changes?(config, _workspace) = !READS.include?(method_of(config))

    def checks?(config, workspace) = !changes?(config, workspace)

    def output_fields(_config) = [ OUTPUT_STATUS, OUTPUT_CONTENT_TYPE, OUTPUT_BODY, DefinedWorkflow::Steps::CallTool::OUTPUT_DATA ]

    def headers_of(config)
      Array(config[KEY_HEADERS]).flat_map { |line| line.to_s.split("\n") }.map(&:strip).compact_blank.to_h do |line|
        found = line.match(HEADER_LINE)
        found ? [ found[1], found[2].strip ] : [ line, nil ]
      end
    end

    def problems(step, workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = []
      found << "#{named} needs the address it calls." if config[KEY_URL].to_s.strip.empty?
      found << "#{named} sends #{METHODS.to_sentence(last_word_connector: ' or ')}." unless METHODS.include?(method_of(config))
      found << "Each header of #{named} reads Name: value." if headers_of(config).values.any?(&:nil?)
      if config[KEY_CONNECTION].present? && !workspace.integrations.where(deleted_at: nil).exists?(slug: config[KEY_CONNECTION].to_s)
        found << "#{named} uses #{config[KEY_CONNECTION]}, which is not a connection here."
      end
      found + undo_problems(step, workspace)
    end

    def reach(config, workspace, **)
      action = Ability::Action.lookup(changes?(config, workspace) ? Ability::Action::HTTP_SEND : Ability::Action::HTTP_READ, workspace)
      action ? [ DefinedWorkflow::Reach::Needed.of_action(action) ] : []
    end

    def describe(config, _workspace) = "#{method_of(config)} #{config[KEY_URL]}".truncate(200)
  end

  def tool_name = label

  def arguments = { KEY_METHOD => self.class.method_of(@config), KEY_URL => @config[KEY_URL].to_s, KEY_CONNECTION => @config[KEY_CONNECTION].presence }.compact

  private

  def label = self.class.label

  def named = self.class.describe(@config, workspace)

  def call(approval_id)
    method = self.class.method_of(@config)
    action_key = changes? ? Ability::Action::HTTP_SEND : Ability::Action::HTTP_READ
    agent_run = Workflow::AgentRun.new(run: @run, record: record, approval_id: approval_id)
    answer = agent_run.tool_call(action_key: action_key, params: arguments) do |authorization|
      found = Workflow::HttpCall.new(workspace).call!(method: method, url: @config[KEY_URL], headers: self.class.headers_of(@config),
                                                      body: @config[KEY_BODY].presence, connection: @config[KEY_CONNECTION].presence)
      authorization.answer_failed!("It answered #{found.status}.") if found.status >= 400
      found
    end.value
    raise Failed, "#{method} #{@config[KEY_URL]} answered #{answer.status}. #{answer.body.to_s.squish.truncate(300)}".strip if answer.status >= 400

    body = answer.body.to_s.truncate(BODY_KEPT)
    { OUTPUT_STATUS => answer.status, OUTPUT_CONTENT_TYPE => answer.content_type, OUTPUT_BODY => body, OUTPUT_DATA => parsed(answer.body) }
  rescue Workflow::HttpCall::Refused => refused
    raise Refused, refused.message
  rescue AbilityGateway::PendingApproval => pending
    wait_for(pending.approval)
  rescue AbilityGateway::Denied
    raise Refused, agent_run.refusal(action_key)
  end
end
