# One handbook page as the Handbook page shows it, with who wrote it, its earlier wordings, where a synced page comes
# from, how Halon reads it, and the reasons an edit or delete is refused.
class HandbookPageSerializer < BaseSerializer
  object_as :page

  HALON_WHOLE = "whole".freeze
  HALON_SEARCHED = "searched".freeze

  type :string
  def id = page.id

  type :string
  def title = page.title

  type "'written' | 'directing' | 'synced'"
  def kind = page.kind

  type :string
  def text = page.text

  # The wording the editor sees, which an edit is made over.
  type :string, optional: true
  def wording_id = page.current_wording&.id

  type :string, optional: true
  def added_by = page.current_wording&.added_by&.display_name

  type :string, optional: true
  def updated_at = page.current_wording&.created_at&.utc&.iso8601

  # Earlier wordings, newest first, each as [id, when, who, text]. Who directs Halon reads with the role it named.
  type "string[][]"
  def history
    page.wordings.reject { |wording| wording.superseded_at.nil? }.reverse.map do |wording|
      [ wording.id, wording.created_at.utc.iso8601, wording.added_by&.display_name.to_s, shown(wording) ]
    end
  end

  type :string, optional: true
  def directing_role_id = (page.current_wording&.directing_role&.id if page.directing?)

  type :string, optional: true
  def directing_role_name = (page.current_wording&.directing_role&.name if page.directing?)

  type :boolean
  def role_set_aside = page.current_wording&.role_set_aside? || false

  # The freezes the page sets, as the form edits them and with the sentence the page shows.
  has_many :freeze_windows, serializer: HandbookFreezeWindowSerializer do
    page.freeze_rules
  end

  # Each heading and the anchor a link Halon cites opens it at, as [heading, anchor].
  type "string[][]"
  def anchors = page.section_anchors.to_a

  type :string, optional: true
  def source_id = page.source_id

  type :string, optional: true
  def source_label = page.source&.label

  type :string, optional: true
  def source_url = page.source_url

  # Whether Halon is given the page whole at the start of a chat, or searches it.
  type "'whole' | 'searched'"
  def halon_reads = options.fetch(:read_whole, []).include?(page.id) ? HALON_WHOLE : HALON_SEARCHED

  type :string, optional: true
  def edit_blocked_reason = page.edit_blocked_reason

  type :string, optional: true
  def delete_blocked_reason = page.delete_blocked_reason

  private

  def shown(wording)
    return wording.text unless page.directing?

    [ "Follows #{wording.incident_role&.name || 'a role since deleted'}.", wording.text.presence ].compact.join(" ")
  end
end
