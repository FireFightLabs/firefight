# Proposes one of the workspace's own skills, new or changed, or a copy of one of Firefight's with changes. A person
# accepts, edits or dismisses it, so a skill never changes on Halon's word alone.
class Chat::Tools::ProposeSkill < RubyLLM::Tool
  def self.tool_name = "propose_skill"

  # Never in a run that only measures Halon.
  def self.all(agent_run)
    return [] unless agent_run.changes_memory?

    [ new(agent_run) ]
  end

  def initialize(agent_run)
    super()
    @agent_run = agent_run
  end

  def name = self.class.tool_name

  def description
    "Propose a skill for this workspace when the person asks to save how to do something as a skill, or when the same " \
      "steps were worked out again that a skill would have saved. Name a skill the workspace has, or one of Firefight's, to " \
      "propose a change to it, keeping everything that still holds, or a new name for a new skill. Write it the way the " \
      "skills use_skill lists are written: when it is used, the tools it needs by the names you call them, and numbered " \
      "steps that name each tool in backticks. Nothing changes until a person accepts it."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "name" => { "type" => "string", "description" => "The skill's name, lowercase words joined by underscores, such as rotate_api_keys" },
        "when" => { "type" => "string", "description" => "When it is used, in one sentence, as use_skill lists it" },
        "tools" => { "type" => "array", "items" => { "type" => "string" }, "description" => "The tools its steps call, by the names you call them" },
        "steps" => { "type" => "string", "description" => "The numbered steps, in Markdown, each tool named in backticks" },
        "reason" => { "type" => "string", "description" => "Why, in one or two sentences, such as \"You rotated keys this way twice this week.\"" }
      },
      "required" => %w[name when tools steps reason]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys
    conversation = @agent_run.chat_owner if @agent_run.chat_owner.is_a?(Conversation)
    content = { "when" => asked["when"], "tools" => Array(asked["tools"]), "steps" => asked["steps"] }
    waiting = waiting_from(conversation, asked["name"])
    return refused(tool_call, "You already proposed #{waiting.custom_skill.name} here, and it still waits on a person.") if waiting

    problem = tools_problem(asked["name"], content["tools"])
    return refused(tool_call, "#{problem} Name the tools as you call them. Nothing was proposed.") if problem

    SkillProposalService.new(@agent_run.workspace).propose!(conversation, name: asked["name"], content: content, reason: asked["reason"].to_s.strip)
    "Proposed. #{where_asked(conversation)} Until someone accepts it, the skill stays as it is."
  rescue ActiveRecord::RecordInvalid => error
    refused(tool_call, "#{error.record.errors.full_messages.to_sentence}. Nothing was proposed.")
  end

  private

  def tools_problem(name, tools)
    workspace = @agent_run.workspace
    wanted = Chat::CustomSkill.normalize_value_for(:name, name)
    Chat::Tools::SkillTools.problem(workspace, tools, skill: Chat::CustomSkill.find_by(workspace: workspace, name: wanted), library: Chat::Skill.find(wanted))
  end

  def waiting_from(conversation, name)
    return unless conversation

    Chat::CustomSkill::Version.proposed.where(conversation: conversation).joins(:custom_skill)
                              .find_by(chat_custom_skills: { name: Chat::CustomSkill.normalize_value_for(:name, name) })
  end

  def where_asked(conversation)
    return "A card in this chat asks the person to accept, edit or dismiss it, and so does the Skills page." if conversation&.personal?
    if SkillProposalService::THREADED_KINDS.include?(conversation&.kind) && conversation.channel_id.present?
      return "A message in this thread asks for it to be accepted or dismissed, and the Skills page also offers to edit it first."
    end

    options = AppUrl.options
    page = options && Rails.application.routes.url_helpers.halon_skills_url(**options)
    "It waits on the Skills page in Firefight#{" (#{page})" if page} for someone to accept, edit or dismiss it. Say so, with the link."
  end

  def refused(tool_call, words)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    words
  end
end
