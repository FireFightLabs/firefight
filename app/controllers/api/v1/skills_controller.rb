# The workspace's own skills, written through the same Chat::CustomSkillService as the Skills page and MCP. Without the
# custom skills flag the endpoints answer as ones that do not exist.
class Api::V1::SkillsController < Api::V1::ApiController
  before_action :require_custom_skills
  before_action :set_skill, only: %i[show update destroy]
  rescue_from Chat::CustomSkillService::Refused, with: :refused

  def index
    authorize!(Ability::Action::RESOURCE_SKILLS, Ability::Action::ACTION_READ)
    @skills = skills.with_usage_counts.includes(:live_version).ordered
  end

  def show
    authorize!(Ability::Action::RESOURCE_SKILLS, Ability::Action::ACTION_READ)
  end

  def create
    authorize!(Ability::Action::RESOURCE_SKILLS, Ability::Action::ACTION_CREATE)

    @skill = service.create!(name: params.require(:name), content: content_param, by: author, reason: params[:reason])
    @skill = skills.with_usage_counts.find(@skill.id)
    render :show, status: :created
  end

  # Only what is sent changes, as a new version. version_id, when sent, refuses a change made over someone else's.
  def update
    authorize!(Ability::Action::RESOURCE_SKILLS, Ability::Action::ACTION_UPDATE)

    enabled = params.key?(:enabled) ? ActiveModel::Type::Boolean.new.cast(params[:enabled]) : nil
    service.update!(@skill, by: author, content: content_param, name: params[:name], reason: params[:reason], seen: params[:version_id], enabled: enabled)
    @skill = skills.with_usage_counts.find(@skill.id)
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_SKILLS, Ability::Action::ACTION_DELETE)

    service.delete!(@skill)
    head :no_content
  end

  private

  def skills = Chat::CustomSkill.where(workspace: current_workspace).live

  def service = Chat::CustomSkillService.new(current_workspace)

  # A personal token writes as its member. A service key writes as nobody, which the skill's history says.
  def author = Current.api_key&.on_behalf_of

  def content_param
    { "when" => params[:when], "tools" => (Array(params[:tools]) if params.key?(:tools)), "steps" => params[:steps] }
  end

  def set_skill
    @skill = skills.with_usage_counts.includes(:live_version).find(params[:id])
  end

  def require_custom_skills
    not_found(nil) unless Chat::CustomSkill.enabled_for?(current_workspace)
  end

  def refused(exception)
    status = exception.message == Chat::CustomSkill::Writing::CHANGED_FIRST ? :conflict : :unprocessable_entity
    render json: error_response(status == :conflict ? "conflict" : "skill_refused", exception.message), status: status
  end
end
