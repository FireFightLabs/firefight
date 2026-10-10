# Every write to a workspace's handbook pages, from the dashboard, the API, MCP, an accepted proposal or a sync, so each
# page is indexed for search again once its words change.
class HandbookService
  # A write a page's own rule refuses, such as editing a synced page, carrying the sentence to show.
  class Blocked < StandardError; end

  def initialize(workspace)
    @workspace = workspace
  end

  # A written page, or the page saying who directs Halon when incident_role is given.
  def create!(title:, text:, by:, incident_role: nil, freeze_windows: [])
    kind = incident_role ? Chat::HandbookPage::KIND_DIRECTING : Chat::HandbookPage::KIND_WRITTEN
    page = Chat::HandbookPage.create_written!(@workspace, title: title, text: text.to_s.strip, by: by, kind: kind, incident_role: incident_role,
                                                          freeze_windows: freeze_windows)
    indexed!(page)
  end

  # Nil when someone changed the page since wording_id, the wording the editor saw.
  def update!(page, text:, by:, title: nil, wording_id: page.current_wording&.id, incident_role: page.current_wording&.incident_role,
              freeze_windows: page.current_wording&.freeze_windows || [])
    refuse!(page.edit_blocked_reason)
    written = page.write!(text: text.to_s.strip, by: by, title: title, wording_id: wording_id, incident_role: incident_role,
                          freeze_windows: freeze_windows)
    indexed!(page) if written
    written
  end

  def delete!(page)
    refuse!(page.delete_blocked_reason)
    page.destroy!
  end

  def reorder!(ordered_ids) = Chat::HandbookPage.reorder!(@workspace, ordered_ids)

  # Splits the page into sections and embeds what changed, in the background.
  def indexed!(page)
    HandbookIndexJob.perform_later(page.id)
    page
  end

  private

  def refuse!(reason)
    raise Blocked, reason if reason
  end
end
