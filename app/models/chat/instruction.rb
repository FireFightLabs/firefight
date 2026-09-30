# How people want Halon to work here, written by them: for the whole workspace, a team, a service, or one resource on
# the map. It is loaded when a chat or run touches what it is for, and never counts as evidence of what happened. An
# edit keeps the old wording as history rather than overwriting it.
class Chat::Instruction < ApplicationRecord
  self.table_name = "chat_instructions"

  TEXT_LIMIT = 2_000
  SCOPE_TYPES = [ CatalogEntry.name, ResourceMap::Resource.name ].freeze

  encrypts :text

  belongs_to :workspace
  belongs_to :scope, polymorphic: true, optional: true
  belongs_to :added_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :superseded_by, class_name: "Chat::Instruction", optional: true

  validates :text, presence: true, length: { maximum: TEXT_LIMIT }
  validates :scope_type, inclusion: { in: SCOPE_TYPES }, allow_nil: true
  validate :one_current_per_scope, on: :create

  scope :current, -> { where(superseded_at: nil) }

  # The notes a chat or run follows: the workspace's, then the teams that own what it touches, then those things
  # themselves, so the most specific note reads last.
  def self.for_subjects(workspace, subjects)
    entries = subjects.grep(CatalogEntry)
    teams = CatalogEntry.where(id: CatalogEntryRelationship.where(source_entry_id: entries.map(&:id)).select(:target_entry_id))
                        .joins(:catalog_type).where(catalog_types: { system_key: CatalogType::SYSTEM_KEY_TEAM })
    scoped = current.where(workspace: workspace)
    workspace_wide = scoped.where(scope_id: nil).to_a
    team_notes = scoped.where(scope: teams.to_a).to_a
    subject_notes = subjects.compact.flat_map { |subject| scoped.where(scope: subject).to_a }
    (workspace_wide + team_notes + subject_notes).uniq
  end

  # Every current note in a workspace paired with its earlier wordings, newest first, found by following which note
  # replaced which, in one query.
  def self.with_history(workspace)
    all = where(workspace: workspace).includes(:scope, :added_by).order(:created_at).to_a
    by_replacement = all.index_by(&:superseded_by_id)
    all.select { |note| note.superseded_at.nil? }.map do |note|
      earlier = []
      current = by_replacement[note.id]
      while current
        earlier << current
        current = by_replacement[current.id]
      end
      [ note, earlier ]
    end
  end

  def about = scope.respond_to?(:name) ? scope.name : nil

  # How Halon reads it, headed by where it applies.
  def line = "#{label}: #{text}"

  # Where the note applies, as Halon and people read it, such as "Auth Service (service)".
  def label
    return "Whole workspace" unless scope

    kind = if scope.is_a?(ResourceMap::Resource) then "resource"
    elsif scope.catalog_type&.system_key == CatalogType::SYSTEM_KEY_TEAM then "team"
    else scope.catalog_type&.name&.downcase || "catalog entry"
    end
    "#{scope.name} (#{kind})"
  end

  # The label inside a sentence, as in "Saved the instructions for the whole workspace."
  def place = scope ? label : "the whole workspace"

  # An edit writes a new note and keeps this one as history. Nil when someone else edited or removed it first.
  def revise!(text:, by:)
    transaction do
      next unless supersede!

      replacement = self.class.create!(workspace: workspace, scope: scope, text: text, added_by: by)
      update_columns(superseded_by_id: replacement.id)
      replacement
    end
  end

  def retire! = supersede!

  private

  def supersede!
    now = Time.current
    return false unless self.class.current.where(id: id).update_all(superseded_at: now, updated_at: now) == 1

    reload
    true
  end

  def one_current_per_scope
    taken = self.class.current.where(workspace_id: workspace_id, scope_type: scope_type, scope_id: scope_id).where.not(id: id).exists?
    errors.add(:base, "#{label} already has instructions. Edit them instead.") if taken
  end
end
