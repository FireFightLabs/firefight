# How people want Halon to work here. The whole workspace's are the handbook, one wording per page, and a team, a
# service or one resource on the map has its own. A chat or run that touches that place loads them, and never counts them as
# evidence of what happened. An edit keeps the old wording as history rather than overwriting it.
class Chat::Instruction < ApplicationRecord
  include Chat::SecretFree
  include Chat::Instruction::Handbook

  self.table_name = "chat_instructions"

  TEXT_LIMIT = 2_000
  SCOPE_TYPES = [ CatalogEntry.name, ResourceMap::Resource.name ].freeze

  encrypts :text

  belongs_to :workspace
  belongs_to :scope, polymorphic: true, optional: true
  belongs_to :added_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :superseded_by, class_name: "Chat::Instruction", optional: true

  # Who directs Halon may say only the role, and a page of freeze windows only its windows.
  validates :text, presence: true, unless: -> { directs? || freeze_windows.present? }
  validates :text, length: { maximum: TEXT_LIMIT }, unless: :handbook?
  validates :text, length: { maximum: Chat::HandbookPage::TEXT_LIMIT }, if: :handbook?
  validates :scope_type, inclusion: { in: SCOPE_TYPES }, allow_nil: true
  validate :one_current_per_scope, on: :create

  scope :current, -> { where(superseded_at: nil) }
  # Every instruction in workspace except those about a resource outside principal's map reach, which read as never there.
  scope :visible_to, ->(principal, workspace) {
    where(workspace: workspace).where("chat_instructions.scope_type IS DISTINCT FROM ?", ResourceMap::Resource.name)
      .or(where(workspace: workspace, scope_type: ResourceMap::Resource.name,
                scope_id: ResourceMap::Resource.visible_to(principal, workspace).select(:id)))
  }

  # The instructions a chat or run follows for what it touches. The teams that own it come first and the things
  # themselves after, so the most specific reads last. Only those principal may see, as for memories. The handbook is read before these.
  def self.for_subjects(workspace, subjects, principal:)
    entries = subjects.grep(CatalogEntry)
    teams = CatalogEntry.where(id: CatalogEntryRelationship.where(source_entry_id: entries.map(&:id)).select(:target_entry_id))
                        .joins(:catalog_type).where(catalog_types: { system_key: CatalogType::SYSTEM_KEY_TEAM }).to_a
    places = (teams + subjects.compact).uniq
    found = visible_to(principal, workspace).for_places.current.includes(:scope).to_a.select { |note| places.include?(note.scope) }
    preload_labels(found.sort_by { |note| places.index(note.scope) })
  end

  # A label names a catalog entry's type, so the types load once for all of them.
  def self.preload_labels(notes)
    ActiveRecord::Associations::Preloader.new(records: notes.map(&:scope).grep(CatalogEntry), associations: :catalog_type).call
    notes
  end

  # Every current set of instructions for a place in a workspace that principal may see, paired with its earlier wordings,
  # newest first, found by following which note replaced which, in one query. The handbook is listed on its own page.
  def self.with_history(workspace, principal:)
    all = preload_labels(visible_to(principal, workspace).for_places.includes(:scope, :added_by).order(:created_at).to_a)
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

  # Where they apply, as Halon and people read it, such as "Auth Service (service)", or a handbook page's title.
  def label
    return handbook_page&.title.to_s unless scope

    kind = if scope.is_a?(ResourceMap::Resource) then "resource"
    elsif scope.catalog_type&.system_key == CatalogType::SYSTEM_KEY_TEAM then "team"
    else scope.catalog_type&.name&.downcase || "catalog entry"
    end
    "#{scope.name} (#{kind})"
  end

  # The label inside a sentence, as in "Saved instructions for Auth Service (service)."
  def place = label

  # An edit writes new instructions and keeps these as history. Nil when someone else edited or removed it first.
  def revise!(text:, by:, incident_role: self.incident_role, freeze_windows: self.freeze_windows)
    transaction do
      next unless supersede!

      replacement = self.class.create!(workspace: workspace, scope: scope, handbook_page: handbook_page, text: text, incident_role: incident_role,
                                       freeze_windows: freeze_windows, added_by: by)
      update_columns(superseded_by_id: replacement.id)
      replacement
    end
  end

  def retire! = supersede!

  # Two people saving the first instructions for one place at the same moment both pass the validation, and the
  # unique index turns the second away with the same sentence.
  def save!(**)
    super
  rescue ActiveRecord::RecordNotUnique
    errors.add(:base, taken_message)
    raise ActiveRecord::RecordInvalid, self
  end

  def save(**)
    super
  rescue ActiveRecord::RecordNotUnique
    errors.add(:base, taken_message)
    false
  end

  private

  def taken_message
    return "Someone changed #{label} first. Read it again before saving." if handbook?

    "#{label} already has instructions. Edit them instead."
  end

  def supersede!
    now = Time.current
    return false unless self.class.current.where(id: id).update_all(superseded_at: now, updated_at: now) == 1

    reload
    true
  end

  def one_current_per_scope
    taken = self.class.current.where(workspace_id: workspace_id, scope_type: scope_type, scope_id: scope_id, handbook_page_id: handbook_page_id).where.not(id: id).exists?
    errors.add(:base, taken_message) if taken
  end
end
