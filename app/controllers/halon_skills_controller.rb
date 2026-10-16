# The workspace's own skills beside Firefight's library: write one, copy one of Firefight's, import or export a SKILL.md
# file, see every version and bring an old one back, decide on what Halon proposed, and take or keep a newer library
# version of a copy.
class HalonSkillsController < InertiaController
  include RequiresAgent

  before_action :require_agent!

  authorizes Ability::Action::RESOURCE_SKILLS,
    read: %i[index export export_library],
    create: %i[create import copy],
    update: %i[update restore take_library keep_own accept_proposal dismiss_proposal enable disable],
    delete: %i[destroy]

  # The query strings that open one of Firefight's skills, a skill's history and Halon's proposal.
  LIBRARY_QUERY = "library".freeze
  HISTORY_QUERY = "history".freeze
  PROPOSAL_QUERY = "proposal".freeze
  # The props loaded only when asked for.
  PROP_TOOL_CHOICES = "toolChoices".freeze
  PROP_LIBRARY_SKILL = "librarySkill".freeze
  PROP_HISTORY = "history".freeze

  def index
    render inertia: "halon/skills", props: {
      skills: HalonSkillSerializer.many(own.live.with_usage_counts.includes(:versions, live_version: :author).ordered.to_a),
      proposals: HalonSkillProposalSerializer.many(proposals.includes(:conversation, custom_skill: :live_version).order(:created_at).to_a),
      library: HalonLibrarySkillSerializer.many(Chat::Skill.library_for(current_workspace), copied: own.live.where.not(library_name: nil).pluck(:library_name)),
      PROP_TOOL_CHOICES => InertiaRails.optional { HalonSkillToolChoiceSerializer.many(Chat::Tools::SkillTools.choices(current_workspace)) },
      PROP_LIBRARY_SKILL => InertiaRails.optional { library_skill_prop },
      PROP_HISTORY => InertiaRails.optional { history_prop }
    }
  end

  def create
    skill = writer.create!(name: params[:name], content: content_param, by: current_membership, reason: params[:reason])
    redirect_to halon_skills_path, notice: "#{skill.name} was added. Halon can load it from its next question."
  rescue ActiveRecord::RecordInvalid => error
    form_refused(error.record)
  rescue Chat::CustomSkillService::ToolsRefused => error
    form_refused_with(tools: [ error.message ])
  end

  def update
    skill = writer.update!(own.live.find(params[:id]), by: current_membership, content: content_param, name: params[:name], reason: params[:reason],
                                                       seen: params[:seen_version_id])
    redirect_to halon_skills_path, notice: "#{skill.name} was updated to version #{skill.live_version.number}."
  rescue ActiveRecord::RecordInvalid => error
    form_refused(error.record)
  rescue Chat::CustomSkillService::ToolsRefused => error
    form_refused_with(tools: [ error.message ])
  rescue Chat::CustomSkill::Writing::Refused => error
    form_refused_with(base: [ error.message ])
  end

  def enable
    skill = own.live.find(params[:id])
    skill.switch!(on: true)
    redirect_to halon_skills_path, notice: "#{skill.name} is on. Halon loads it again."
  end

  # Off, Halon no longer loads it, and a workflow step that runs it is refused at publish and fails at run time. A copy
  # switched off leaves Firefight's skill of its name in its place.
  def disable
    skill = own.live.find(params[:id])
    skill.switch!(on: false)
    redirect_to halon_skills_path, notice: disabled_notice(skill)
  end

  def destroy
    skill = own.live.with_usage_counts.find(params[:id])
    blocked = skill.deletion_blocked_reason
    return redirect_to(halon_skills_path, alert: blocked) if blocked

    skill.destroy!
    redirect_to halon_skills_path, notice: deleted_notice(skill)
  end

  # A SKILL.md of a skill the workspace has becomes its next version, of one of Firefight's its copy, and otherwise a new skill.
  def import
    parsed = Chat::CustomSkill::Document.parse(uploaded_text)
    skill = own.find_by(name: Chat::CustomSkill.normalize_value_for(:name, parsed.name))
    problem = Chat::Tools::SkillTools.problem(current_workspace, parsed.content["tools"], skill: skill, library: library_named(parsed.name))
    return form_refused_with(file: [ problem ]) if problem

    skill, version = Chat::CustomSkill::Document.import!(parsed, workspace: current_workspace, by: current_membership)
    notice = version ? "#{skill.name} was updated from the file, as version #{version.number}." : "#{skill.name} was imported. Halon can load it from its next question."
    redirect_to halon_skills_path, notice: notice
  rescue Chat::CustomSkill::Document::Unreadable, Chat::CustomSkill::Writing::Refused => error
    form_refused_with(file: [ error.message ])
  rescue ActiveRecord::RecordInvalid => error
    form_refused_with(file: error.record.errors.full_messages)
  end

  def export
    skill = own.live.includes(:live_version).find(params[:id])
    send_skill(skill.definition)
  end

  def export_library
    send_skill(library_skill!)
  end

  def copy
    library = library_skill!
    blocked = Chat::CustomSkill.copy_blocked_reason(library, workspace: current_workspace)
    return redirect_to(halon_skills_path, alert: blocked) if blocked

    copied = Chat::CustomSkill.copy!(library, workspace: current_workspace, by: current_membership)
    redirect_to halon_skills_path, notice: "#{copied.name} was copied. Halon uses your copy in place of Firefight's from now on."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to halon_skills_path, alert: error.record.errors.full_messages.to_sentence
  end

  def restore
    skill = own.live.find(params[:id])
    version = skill.versions.find(params[:version_id])
    restored = skill.restore!(version, by: current_membership)
    redirect_to halon_skills_path, notice: "#{skill.name} says what version #{version.number} said again, as version #{restored.number}."
  rescue Chat::CustomSkill::Writing::Refused => error
    redirect_to halon_skills_path, alert: error.message
  rescue ActiveRecord::RecordInvalid => error
    redirect_to halon_skills_path, alert: error.record.errors.full_messages.to_sentence
  end

  def take_library
    skill = own.live.find(params[:id])
    skill.take_library!(by: current_membership)
    redirect_to halon_skills_path, notice: "#{skill.name} now says what Firefight's version #{skill.library_version} says."
  rescue Chat::CustomSkill::Writing::Refused => error
    redirect_to halon_skills_path, alert: error.message
  rescue ActiveRecord::RecordInvalid => error
    redirect_to halon_skills_path, alert: error.record.errors.full_messages.to_sentence
  end

  def keep_own
    skill = own.live.find(params[:id])
    skill.keep_own!
    redirect_to halon_skills_path, notice: "#{skill.name} keeps your words. You are told again when Firefight ships a newer version."
  rescue Chat::CustomSkill::Writing::Refused => error
    redirect_to halon_skills_path, alert: error.message
  end

  # Accepting works from this page and from the card in the chat where Halon proposed it, and each goes back to where it
  # was pressed. A proposal edited first carries the person's words.
  def accept_proposal
    proposal = proposals.find(params[:id])
    skill = proposal.custom_skill
    was_new = skill.live_version_id.nil?
    edited = params.key?(:steps)
    return if edited && tools_refused?(skill)

    SkillProposalService.new(current_workspace).accept!(proposal, by: current_membership, content: (content_param if edited), name: (params[:name] if edited))
    redirect_back_or_to halon_skills_path, notice: "#{skill.name} was #{was_new ? 'added' : 'updated'}#{' with your edit' if edited}. Halon loads it as it now reads."
  rescue Chat::CustomSkill::Writing::Refused => error
    edited ? form_refused_with(base: [ error.message ]) : redirect_back_or_to(halon_skills_path, alert: error.message)
  rescue ActiveRecord::RecordInvalid => error
    form_refused(error.record)
  end

  def dismiss_proposal
    proposal = proposals.find(params[:id])
    SkillProposalService.new(current_workspace).dismiss!(proposal, by: current_membership)
    redirect_back_or_to halon_skills_path, notice: "Halon's proposed #{proposal.custom_skill.name} was dismissed. Your skills are unchanged."
  rescue Chat::CustomSkill::Writing::Refused => error
    redirect_back_or_to halon_skills_path, alert: error.message
  end

  private

  def own = Chat::CustomSkill.where(workspace: current_workspace)

  def writer = Chat::CustomSkillService.new(current_workspace)

  def proposals = Chat::CustomSkill::Version.proposed.joins(:custom_skill).where(chat_custom_skills: { workspace_id: current_workspace.id })

  def content_param
    { "when" => params[:when], "tools" => Array(params[:tools]), "steps" => params[:steps],
      "references" => Array(params[:references]), "signals" => Array(params[:signals]) }
  end

  def library_named(name) = Chat::Skill.library_for(current_workspace).find { |skill| skill.name == Chat::CustomSkill.normalize_value_for(:name, name) }

  # Refuses the form beside its tools when one is not a tool Halon has here. A skill written from scratch is checked as the
  # workspace's own, and one of its own as the copy it may be.
  def tools_refused?(skill = nil)
    problem = Chat::Tools::SkillTools.problem(current_workspace, content_param["tools"], skill: skill)
    form_refused_with(tools: [ problem ]) if problem
    problem.present?
  end

  def library_skill! = Chat::Skill.library_for(current_workspace).find { |skill| skill.name == params[:name].to_s } || raise(ActiveRecord::RecordNotFound)

  def library_skill_prop
    wanted = params[LIBRARY_QUERY].to_s
    found = wanted.present? && Chat::Skill.library_for(current_workspace).find { |skill| skill.name == wanted }
    found ? HalonLibrarySkillSerializer.one(found, copied: [], with_steps: true) : nil
  end

  def history_prop
    skill = params[HISTORY_QUERY].present? && own.live.find_by(id: params[HISTORY_QUERY])
    skill ? HalonSkillVersionSerializer.many(skill.versions.where.not(status: Chat::CustomSkill::Version::STATUS_PROPOSED).includes(:author, :decided_by).newest_first.to_a) : nil
  end

  def uploaded_text
    file = params[:file]
    raise Chat::CustomSkill::Document::Unreadable, "Choose a SKILL.md file to import." unless file.respond_to?(:read)

    file.read(Chat::CustomSkill::Document::SIZE_LIMIT + 1)
  end

  def send_skill(definition)
    send_data Chat::CustomSkill::Document.render(definition), filename: Chat::CustomSkill::Document::FILE_NAME, type: "text/markdown; charset=utf-8",
                                                               disposition: "attachment"
  end

  def disabled_notice(skill)
    return "#{skill.name} is off. Halon uses Firefight's #{skill.library_name} until you turn your copy back on." if skill.copy?

    "#{skill.name} is off. Halon no longer loads it, and a workflow step that runs it is refused until you turn it back on."
  end

  def deleted_notice(skill)
    return "#{skill.name} was deleted. Halon uses Firefight's #{skill.library_name} again." if skill.copy? && skill.library_skill

    "#{skill.name} was deleted. Halon no longer loads it."
  end

  # Back to the form that was saved, with why beside the field it is about, so nothing written is lost.
  def form_refused(record)
    errors = record.errors.to_hash.transform_keys { |key| key == :used_when ? :when : key }
    form_refused_with(errors)
  end

  def form_refused_with(errors) = redirect_back_or_to(halon_skills_path, inertia: { errors: errors })
end
