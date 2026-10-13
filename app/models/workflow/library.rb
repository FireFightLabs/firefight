# Firefight's own workflows, in two kinds.
#
# Items, kept as data in config/workflow_library/<key>.yml: a name, what it does, other names, and the trigger, steps,
# edges and outputs of a workflow version. Each carries a version (FirefightLibrary). A workspace uses one as it is, and
# moves with each new version while its steps stay Firefight's, or copies it, and is told when a newer one exists with
# what changed. An item whose steps the workspace cannot run is listed but cannot be taken.
#
# Templates, which a person starts from the Workflows page in one click and Halon proposes from a chat. Each builds a
# workflow's content from a few answers, such as which resource and when, into a draft attributed to whoever made it.
#
# Either way the workflow is a draft until it is published through WorkflowPublishService, which grants its own identity
# what its steps need, and it runs on the workflow runtime like any other.
module Workflow::Library
  KEY_CHECK_LATER = "check_later".freeze
  KEY_PROBING_SCAN = "probing_scan".freeze
  KEYS = [ KEY_CHECK_LATER, KEY_PROBING_SCAN ].freeze

  Template = Data.define(:key, :name, :description)
  TEMPLATES = {
    KEY_CHECK_LATER => Template.new(key: KEY_CHECK_LATER, name: "Check something later",
                                    description: "Reads how a resource stands and its error rate and latency against normal at a time you choose, has Halon judge it and posts the verdict."),
    KEY_PROBING_SCAN => Template.new(key: KEY_PROBING_SCAN, name: "Look for probing in the logs",
                                     description: "Every weekday at 09:00, Halon looks through the last day of logs for scanners and probing and raises a security notice when it finds some.")
  }.freeze

  PARAM_RESOURCE = "resource".freeze
  PARAM_AT = "at".freeze
  PARAM_TIME_ZONE = "time_zone".freeze
  PARAM_CHANNEL = "channel".freeze
  PARAM_REPLY_IN_CHAT = "reply_in_chat".freeze
  PARAM_DAYS = "days".freeze

  class Refused < StandardError; end

  DIRECTORY = Rails.root.join("config/workflow_library")

  Item = Data.define(:key, :name, :description, :aliases, :definition, :version) do
    def trigger = definition["trigger"]

    # Why it cannot be used in this workspace yet, as each sentence publishing it would be refused with, such as a skill
    # its steps follow that this workspace's connections do not offer.
    def problems(workspace) = Workflow::Version.new(workflow: Workflow.new(workspace: workspace), **definition.symbolize_keys).problems

    def available?(workspace) = problems(workspace).empty?

    def digest = Digest::SHA256.hexdigest(definition.merge("name" => name, "description" => description, "aliases" => aliases).to_json)
  end

  module_function

  def all
    @all ||= Dir[DIRECTORY.join("*.yml")].sort.map { |path| parse(path) }.freeze
  end

  def find(key) = all.find { |item| item.key == key.to_s }

  # What each item says, by key, which its library version is kept against.
  def digests = all.to_h { |item| [ item.key, item.digest ] }

  def parse(path)
    key = File.basename(path, ".yml")
    data = YAML.safe_load_file(path)
    Item.new(
      key: key, name: data.fetch("name"), description: data.fetch("description"), aliases: Array(data["aliases"]),
      definition: data.slice(*Workflow::Version::CONTENT).reverse_merge("edges" => [], "outputs" => {}),
      version: FirefightLibrary.version(FirefightLibrary::KIND_WORKFLOWS, key)
    )
  end

  # Moves every workflow that follows an item on to the item's current version. Each moves in its own transaction, so
  # one that cannot is left as it was and logged, and the rest still move.
  def upgrade_all!
    all.each do |item|
      Workflow.where(library_key: item.key, follows_library: true).where("library_version < ?", item.version).find_each do |workflow|
        workflow.upgrade_from_library!
      rescue ActiveRecord::ActiveRecordError => error
        Rails.logger.error({ event: "workflow_library.upgrade_failed", workflow_id: workflow.id, library_key: item.key, version: item.version,
                             error: error.class.name, message: error.message })
      end
    end
  end

  def template(key) = TEMPLATES.fetch(key.to_s) { raise Refused, "There is no workflow called #{key} in the library." }

  # A new draft workflow made from a template, its content added one attributed edit at a time. halon marks Halon as
  # the one making it, with its reason.
  def create!(workspace:, key:, params:, by:, name: nil, halon: false, reason: nil, origin_conversation: nil)
    found = template(key)
    params = params.to_h.stringify_keys
    content = content_for(workspace, found.key, params)
    workflow = Workflow.transaction do
      made = Workflow.create!(workspace: workspace, name: name.presence || default_name(found, params), description: found.description,
                              created_by: by, origin_conversation: origin_conversation)
      edit = ->(operation, payload) { made.edit!(operation: operation, payload: payload, by: by, halon: halon, reason: reason || "Made from #{found.name} in the library.") }
      edit.call(Workflow::Edit::OPERATION_CHANGE_TRIGGER, { trigger: content[:trigger] })
      content[:steps].each { |step| edit.call(Workflow::Edit::OPERATION_ADD_STEP, { step: step }) }
      content[:edges].each { |connection| edit.call(Workflow::Edit::OPERATION_CONNECT, connection) }
      made
    end
    workflow.ensure_agent!
    workflow
  end

  def default_name(found, params)
    return "Check #{params[PARAM_RESOURCE]}" if found.key == KEY_CHECK_LATER && params[PARAM_RESOURCE].present?

    found.name
  end

  def content_for(workspace, key, params)
    case key
    when KEY_CHECK_LATER then check_later(params)
    when KEY_PROBING_SCAN then probing_scan(workspace, params)
    end
  end

  def step(name, kind, config, **settings) = { "id" => "step_#{name}", "name" => name, "kind" => kind, "config" => config }.merge(settings.stringify_keys)

  def edge(from, to, route = nil) = { "from" => "step_#{from}", "to" => "step_#{to}", "route" => route }.compact

  # Once at a time: reads the resource's status and its key reads against normal, Halon judges them, and the verdict is
  # posted in a channel or back where it was asked for.
  def check_later(params)
    resource = params[PARAM_RESOURCE].to_s.strip
    raise Refused, "Say which resource to check." if resource.empty?

    reply = ActiveModel::Type::Boolean.new.cast(params[PARAM_REPLY_IN_CHAT]) == true
    raise Refused, "Say which channel to post the verdict in." if !reply && params[PARAM_CHANNEL].to_s.strip.empty?

    read = { DefinedWorkflow::Steps::CallTool::KEY_ARGUMENTS => { Integrations::Capabilities::RESOURCE_ARG => resource } }
    {
      trigger: { Workflow::Trigger::KEY_KIND => Workflow::Trigger::KIND_ONCE_AT, Workflow::Trigger::KEY_INPUTS => [],
                 Workflow::Trigger::Schedule::KEY_AT => params[PARAM_AT].to_s, Workflow::Trigger::Schedule::KEY_TIME_ZONE => params[PARAM_TIME_ZONE].to_s },
      steps: [
        step("status", DefinedWorkflow::Steps::CallTool.kind, read.merge(DefinedWorkflow::Steps::CallTool::KEY_TOOL => Integrations::Capabilities.spec(Integrations::Capabilities::STATUS).tool_name),
             on_failure: DefinedWorkflow::ON_FAILURE_CONTINUE),
        step("against_normal", DefinedWorkflow::Steps::CallTool.kind, read.merge(DefinedWorkflow::Steps::CallTool::KEY_TOOL => Integrations::Capabilities::KEY_QUERY_TOOL),
             on_failure: DefinedWorkflow::ON_FAILURE_CONTINUE),
        step("judge", DefinedWorkflow::Steps::AskHalon.kind, {
          DefinedWorkflow::Steps::AskHalon::KEY_QUESTION => "Is #{resource} healthy now, and are its error rate and latency within its normal?",
          DefinedWorkflow::Steps::AskHalon::KEY_DATA => { "status" => "{{steps.status.answer}}", "against_normal" => "{{steps.against_normal.answer}}" }
        }),
        step("tell", DefinedWorkflow::Steps::PostToChannel.kind, {
          DefinedWorkflow::Steps::PostToChannel::KEY_CHANNEL => (params[PARAM_CHANNEL].to_s.strip unless reply),
          DefinedWorkflow::Steps::PostToChannel::KEY_REPLY => (true if reply),
          DefinedWorkflow::Steps::PostToChannel::KEY_MESSAGE => "#{resource}, checked as asked: {{steps.judge.verdict}}. {{steps.judge.summary}}"
        }.compact)
      ],
      edges: [ edge("status", "judge"), edge("against_normal", "judge"), edge("judge", "tell") ]
    }
  end

  # On a schedule, Halon follows probing_scan through the logs, after reading each connected edge network's security
  # events, and a security notice is raised when it found probing. It says nothing when it found none.
  def probing_scan(workspace, params)
    days = Array(params[PARAM_DAYS].presence || Workflow::Trigger::Schedule::WEEKDAYS).map(&:to_i)
    edges_read = Chat::Skill.coverage(workspace, Chat::Skill::SIGNAL_SECURITY_EVENTS).skills
    edge_steps = edges_read.each_with_index.map do |skill, index|
      step("edge_#{index + 1}", DefinedWorkflow::Steps::RunSkill.kind, {
        DefinedWorkflow::Steps::RunSkill::KEY_SKILL => skill.name,
        DefinedWorkflow::Steps::RunSkill::KEY_FOCUS => "Only read. The last 24 hours of security events: the top client addresses, networks, paths and user agents, " \
                                                       "and what was blocked or challenged."
      }, on_failure: DefinedWorkflow::ON_FAILURE_CONTINUE)
    end
    edge_words = edge_steps.map { |each| "{{steps.#{each['name']}.summary}}" }.join(" ")
    focus = "The last 24 hours."
    focus += " Weigh what the edge network's security events showed too: #{edge_words}" if edge_steps.any?
    {
      trigger: { Workflow::Trigger::KEY_KIND => Workflow::Trigger::KIND_SCHEDULE, Workflow::Trigger::KEY_INPUTS => [],
                 Workflow::Trigger::Schedule::KEY_REPEAT => Workflow::Trigger::Schedule::REPEAT_DAYS, Workflow::Trigger::Schedule::KEY_DAYS => days,
                 Workflow::Trigger::Schedule::KEY_AT => params[PARAM_AT].presence || "09:00", Workflow::Trigger::Schedule::KEY_TIME_ZONE => params[PARAM_TIME_ZONE].to_s },
      steps: [
        *edge_steps,
        step("scan", DefinedWorkflow::Steps::RunSkill.kind, { DefinedWorkflow::Steps::RunSkill::KEY_SKILL => KEY_PROBING_SCAN, DefinedWorkflow::Steps::RunSkill::KEY_FOCUS => focus }),
        step("decide", DefinedWorkflow::Steps::Branch.kind, {
          "routes" => [ { "route" => "found", "when" => { "left" => "{{steps.scan.verdict}}", "operator" => DefinedWorkflow::CONDITION_EQUALS,
                                                           "right" => FirefightAi::Schemas::WorkflowAnswer::PROBLEM } } ],
          "otherwise" => "clear"
        }),
        step("notice", DefinedWorkflow::Steps::RaiseNotice.kind, {
          DefinedWorkflow::Steps::RaiseNotice::KEY_SIGNAL => Investigation::Notice::SIGNAL_PROBING,
          DefinedWorkflow::Steps::RaiseNotice::KEY_TOPIC => "Probing of the team's services",
          DefinedWorkflow::Steps::RaiseNotice::KEY_SUMMARY => "{{steps.scan.summary}}",
          DefinedWorkflow::Steps::RaiseNotice::KEY_SEVERITY => "{{steps.scan.severity}}"
        })
      ],
      edges: [ *edge_steps.map { |each| { "from" => each["id"], "to" => "step_scan" } }, edge("scan", "decide"), edge("decide", "notice", "found") ]
    }
  end
end
