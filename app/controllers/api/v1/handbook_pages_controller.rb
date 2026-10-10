# The workspace's handbook pages, through the same HandbookService the dashboard and MCP write through. A synced page is
# read here and changed only at its source.
class Api::V1::HandbookPagesController < Api::V1::ApiController
  CHANGED_FIRST = "Someone changed this page first. Read it again before saving.".freeze

  before_action :set_page, only: %i[show update destroy]
  rescue_from HandbookService::Blocked, with: :blocked

  def index
    authorize!(Ability::Action::RESOURCE_HANDBOOK, Ability::Action::ACTION_READ)
    @pages = pages.ordered.includes(:source, current_wording: :incident_role)
  end

  def show
    authorize!(Ability::Action::RESOURCE_HANDBOOK, Ability::Action::ACTION_READ)
  end

  # A page with incident_role names the role Halon takes direction from in an incident.
  def create
    authorize!(Ability::Action::RESOURCE_HANDBOOK, Ability::Action::ACTION_CREATE)

    role = role_param
    @page = service.create!(title: params.require(:title), text: params[:text], by: author, incident_role: role, freeze_windows: role ? [] : freeze_windows_param)
    render :show, status: :created
  end

  # Only what is sent changes. wording_id, when sent, refuses an edit made over someone else's.
  def update
    authorize!(Ability::Action::RESOURCE_HANDBOOK, Ability::Action::ACTION_UPDATE)

    written = service.update!(@page, text: params.key?(:text) ? params[:text] : @page.text, title: params[:title], by: author,
                                     wording_id: params[:wording_id].presence || @page.current_wording&.id,
                                     incident_role: @page.directing? ? (role_param || @page.current_wording&.incident_role) : nil,
                                     freeze_windows: params.key?(:freeze_windows) ? freeze_windows_param : @page.current_wording&.freeze_windows)
    return render(json: error_response("conflict", CHANGED_FIRST), status: :conflict) unless written

    @page.reload
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_HANDBOOK, Ability::Action::ACTION_DELETE)

    service.delete!(@page)
    head :no_content
  end

  private

  def pages = Chat::HandbookPage.where(workspace: current_workspace)

  def service = HandbookService.new(current_workspace)

  # A personal token writes as its member. A service key writes as nobody, which the page's history says.
  def author = Current.api_key&.on_behalf_of

  def set_page
    @page = pages.includes(:source, current_wording: :incident_role).find(params[:id])
  end

  def freeze_windows_param = Array(params[:freeze_windows]).map { |window| window.respond_to?(:to_unsafe_h) ? window.to_unsafe_h : window }

  def role_param
    return nil if params[:incident_role].blank?

    current_workspace.incident_roles.active.find_by!(slug: params[:incident_role].to_s)
  end

  def blocked(exception)
    render json: error_response("page_synced", exception.message), status: :unprocessable_entity
  end
end
