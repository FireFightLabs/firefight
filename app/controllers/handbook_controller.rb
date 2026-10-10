# The workspace's handbook, where people write down how the workspace works page by page, sync pages from a repository or
# a connected tool, ask Halon to draft it, and decide on the edits Halon proposes.
class HandbookController < InertiaController
  authorizes Ability::Action::RESOURCE_HANDBOOK,
    read: %i[index],
    create: %i[create_page create_source],
    update: %i[update_page reorder sync_source accept_proposal dismiss_proposal],
    delete: %i[destroy_page destroy_source]
  # Drafting asks Halon, which spends money like any question.
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, create: %i[draft]

  CHANGED_FIRST = "Someone changed this page first. Their version is shown now.".freeze
  # The query string the page opens one of Halon's proposals by.
  PROPOSAL_QUERY = "proposal".freeze

  include RequiresAgent
  before_action :require_agent!

  def index
    pages = handbook.ordered.includes(:source, current_wording: %i[added_by incident_role], wordings: %i[added_by incident_role]).to_a
    render inertia: "handbook/index", props: {
      pages: HandbookPageSerializer.many(pages, read_whole: Chat::HandbookPage.for_halon(current_workspace).whole.map(&:id)),
      suggestions: HandbookSuggestionSerializer.many(Chat::HandbookPage::SUGGESTIONS),
      directingRole: Chat::HandbookPage.directing_role(current_workspace)&.name,
      proposals: HandbookProposalSerializer.many(proposals.pending.newest_first.includes(:handbook_page, :conversation, :incident, :investigation)),
      sources: HandbookSourceSerializer.many(current_workspace_sources),
      roles: HandbookRoleSerializer.many(current_workspace.incident_roles.active.ordered),
      timeZones: Workspace::FreezeWindows.time_zones,
      importers: HandbookImporterSerializer.many(importers, principal: current_membership)
    }
  end

  def create_page
    role = role_param
    page = service.create!(title: params[:title], text: params[:text], by: current_membership, incident_role: role,
                           freeze_windows: role ? [] : freeze_windows_param)
    redirect_to page_path(page), notice: "#{page.title} was added. Halon follows it from its next chat or investigation."
  rescue ActiveRecord::RecordInvalid => error
    form_refused(error.record.errors.to_hash)
  end

  def update_page
    page = handbook.find(params[:id])
    written = service.update!(page, text: params[:text], title: params[:title], by: current_membership, wording_id: params[:wording_id],
                                    incident_role: page.directing? ? role_param : nil,
                                    freeze_windows: params.key?(:freeze_windows) ? freeze_windows_param : page.current_wording&.freeze_windows)
    return form_refused({ base: [ CHANGED_FIRST ] }) unless written

    redirect_to page_path(page), notice: "#{page.title} was updated. The earlier wording is kept as history."
  rescue ActiveRecord::RecordInvalid => error
    form_refused(error.record.errors.to_hash)
  rescue HandbookService::Blocked => error
    form_refused({ base: [ error.message ] })
  end

  def destroy_page
    page = handbook.find(params[:id])
    service.delete!(page)
    redirect_to settings_handbook_path, notice: "#{page.title} was deleted. Halon no longer follows it."
  rescue HandbookService::Blocked => error
    redirect_to page_path(page), alert: error.message
  end

  def reorder
    service.reorder!(Array(params.require(:ordered_ids)))
    redirect_to settings_handbook_path, notice: "Page order updated."
  end

  def create_source
    source = Chat::HandbookSource.create!(workspace: current_workspace, integration: importer_param, kind: params[:kind].to_s,
                                          repository: params[:repository].presence, path: params[:path].presence,
                                          reference: params[:reference].presence, added_by: current_membership)
    HandbookSyncJob.perform_later(source.id)
    redirect_to settings_handbook_path, notice: "Importing #{source.label}. Its pages appear here once they are read."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to settings_handbook_path, alert: error.record.errors.full_messages.to_sentence
  end

  def sync_source
    source = current_workspace_sources.find(params[:id])
    HandbookSyncJob.perform_later(source.id)
    redirect_to settings_handbook_path, notice: "Syncing #{source.label} now."
  end

  def destroy_source
    source = current_workspace_sources.find(params[:id])
    label = source.label
    source.destroy!
    redirect_to settings_handbook_path, notice: "Stopped syncing #{label}. Its pages were removed."
  end

  # Starts a chat in which Halon reads the map, the repositories, CI and past incidents, and proposes pages for a person to
  # accept, each a card in the chat and on this page.
  def draft
    chat = Conversation::Asking.start_personal(workspace: current_workspace, member: current_membership, question: Chat::HandbookPage::DRAFT_REQUEST)
    redirect_to agent_chat_path(chat), notice: "Halon is drafting your handbook. Its pages arrive as proposals to accept, in the chat and on the Handbook page."
  end

  # Deciding works from the Handbook page and from a card in a chat, and each goes back to where it was pressed. text is
  # the person's edit, when they changed the wording first.
  def accept_proposal
    proposal = proposals.find(params[:id])
    blocked = proposal.accept_blocked_reason
    return redirect_back_or_to(settings_handbook_path, alert: blocked) if blocked

    written = HandbookProposalService.new(current_workspace).accept!(proposal, by: current_membership, text: params[:text])
    return redirect_back_or_to(settings_handbook_path, alert: proposal.accept_blocked_reason || CHANGED_FIRST) unless written

    redirect_back_or_to settings_handbook_path, notice: accepted_notice(proposal)
  rescue ActiveRecord::RecordInvalid => error
    redirect_back_or_to settings_handbook_path, alert: error.record.errors.full_messages.to_sentence
  end

  def dismiss_proposal
    proposal = proposals.find(params[:id])
    dismissed = proposal.dismiss_blocked_reason.nil? && HandbookProposalService.new(current_workspace).dismiss!(proposal, by: current_membership)
    return redirect_back_or_to(settings_handbook_path, alert: proposal.reload.dismiss_blocked_reason || CHANGED_FIRST) unless dismissed

    redirect_back_or_to settings_handbook_path, notice: "The proposed #{proposal.what} was dismissed. The handbook is unchanged."
  end

  private

  def service = @service ||= HandbookService.new(current_workspace)

  def handbook = Chat::HandbookPage.where(workspace: current_workspace)

  def proposals = Chat::HandbookProposal.where(workspace: current_workspace)

  def current_workspace_sources = Chat::HandbookSource.where(workspace: current_workspace).includes(:integration, :pages).order(:created_at)

  def page_path(page) = settings_handbook_path(Chat::HandbookPage::PAGE_QUERY => page.id)

  # Back to the form that was saved, with why beside the field it is about, so nothing written is lost.
  def form_refused(errors) = redirect_back_or_to(settings_handbook_path, inertia: { errors: errors })

  def accepted_notice(proposal)
    edited = proposal.edited ? " with your edit" : ""
    return "#{proposal.page_title} was added#{edited}. Halon follows it from its next chat or investigation." if proposal.title.present?

    "#{proposal.page_title} was updated#{edited}. The earlier wording is kept as history."
  end

  # The connections a page can be synced from, each a code host that reads repositories or a tool that keeps documents.
  def importers
    current_workspace.integrations.active.order(:name).select do |integration|
      Integrations::RepositoryDocuments.reads?(integration) || Integrations::Documents.reads?(integration)
    end
  end

  def importer_param
    importers.find { |integration| integration.id == params[:integration_id].to_s } || raise(ActiveRecord::RecordNotFound)
  end

  # Each freeze window as the page form sends it, read by Workspace::FreezeWindows::Rule.
  def freeze_windows_param = Array(params[:freeze_windows]).map { |window| window.respond_to?(:to_unsafe_h) ? window.to_unsafe_h : window }

  def role_param
    return nil if params[:incident_role_id].blank?

    current_workspace.incident_roles.active.find(params[:incident_role_id])
  end
end
