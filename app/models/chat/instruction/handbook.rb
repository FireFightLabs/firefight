# The whole workspace's instructions are the handbook. Each wording belongs to a handbook page, and an edit keeps the
# page's earlier wordings as history. Instructions for a team, a service or a resource stay on the Memory page.
module Chat::Instruction::Handbook
  extend ActiveSupport::Concern

  WHOLE_WORKSPACE_ELSEWHERE = "Instructions for the whole workspace are written in the handbook.".freeze

  included do
    belongs_to :handbook_page, class_name: "Chat::HandbookPage", optional: true
    belongs_to :incident_role, optional: true
    # The page saying who directs Halon may be a role alone, and the column holds no nulls.
    normalizes :text, with: ->(value) { value.to_s }, apply_to_nil: true

    validate :page_or_place
    validate :role_only_where_it_directs
    validate :freeze_windows_hold

    scope :in_handbook, -> { where.not(handbook_page_id: nil) }
    scope :for_places, -> { where(handbook_page_id: nil) }
  end

  def handbook? = handbook_page_id.present?

  def directs? = handbook_page&.directing? || false

  # Set aside since it was chosen, so Halon follows the Incident Lead until someone chooses again.
  def role_set_aside? = directs? && (incident_role.nil? || !incident_role.enabled?)

  def directing_role = role_set_aside? ? Chat::HandbookPage.lead_role(workspace) : incident_role

  # The freezes this wording sets, which plans keep out of.
  def freeze_rules = Array(freeze_windows).map { |window| Workspace::FreezeWindows::Rule.from(window) }

  # Kept as each rule stores itself, so a wording holds only the fields its repeat uses.
  def freeze_windows=(windows)
    super(Array(windows).map { |window| Workspace::FreezeWindows::Rule.from(window).stored })
  end

  private

  def page_or_place
    if scope_type.nil? && handbook_page_id.nil?
      errors.add(:base, WHOLE_WORKSPACE_ELSEWHERE)
    elsif scope_type.present? && handbook_page_id.present?
      errors.add(:handbook_page, "is only for the whole workspace")
    end
  end

  def freeze_windows_hold
    return if freeze_windows.blank?
    return errors.add(:freeze_windows, "are only for a handbook page people write") unless handbook_page && !handbook_page.synced? && !handbook_page.directing?
    return errors.add(:base, "A page holds at most #{Workspace::FreezeWindows::PER_PAGE} freeze windows.") if freeze_windows.size > Workspace::FreezeWindows::PER_PAGE

    freeze_rules.flat_map(&:problems).uniq.each { |problem| errors.add(:base, problem) }
  end

  def role_only_where_it_directs
    if directs?
      errors.add(:base, "Choose the role Halon takes direction from.") unless incident_role
      errors.add(:base, "That role is not in this workspace.") if incident_role && incident_role.workspace_id != workspace_id
    elsif incident_role_id
      errors.add(:incident_role, "is only for who directs Halon")
    end
  end
end
