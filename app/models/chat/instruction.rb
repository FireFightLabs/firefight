# How people want Halon to work here. They write them for the whole workspace, a team, a service, or one resource on
# the map. A chat or run that touches that place loads them, and never counts them as evidence of what happened. An
# edit keeps the old wording as history rather than overwriting it.
class Chat::Instruction < ApplicationRecord
  include Chat::SecretFree

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

  # The instructions a chat or run follows: the workspace's, then the teams that own what it touches, then those
  # things themselves, so the most specific reads last.
  def self.for_subjects(workspace, subjects)
    entries = subjects.grep(CatalogEntry)
    teams = CatalogEntry.where(id: CatalogEntryRelationship.where(source_entry_id: entries.map(&:id)).select(:target_entry_id))
                        .joins(:catalog_type).where(catalog_types: { system_key: CatalogType::SYSTEM_KEY_TEAM }).to_a
    places = (teams + subjects.compact).uniq
    found = current.where(workspace: workspace).includes(:scope).to_a
                   .select { |note| note.scope_id.nil? || places.include?(note.scope) }
    order = [ nil ] + places
    preload_labels(found.sort_by { |note| order.index(note.scope) })
  end

  # A label names a catalog entry's type, so the types load once for all of them.
  def self.preload_labels(notes)
    ActiveRecord::Associations::Preloader.new(records: notes.map(&:scope).grep(CatalogEntry), associations: :catalog_type).call
    notes
  end

  # Every current set of instructions in a workspace paired with its earlier wordings, newest first, found by following which note
  # replaced which, in one query.
  def self.with_history(workspace)
    all = preload_labels(where(workspace: workspace).includes(:scope, :added_by).order(:created_at).to_a)
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

  # Where they apply, as Halon and people read it, such as "Auth Service (service)".
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

  # An edit writes new instructions and keeps these as history. Nil when someone else edited or removed it first.
  def revise!(text:, by:)
    transaction do
      next unless supersede!

      replacement = self.class.create!(workspace: workspace, scope: scope, text: text, added_by: by)
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

  def taken_message = "#{label} already has instructions. Edit them instead."

  def supersede!
    now = Time.current
    return false unless self.class.current.where(id: id).update_all(superseded_at: now, updated_at: now) == 1

    reload
    true
  end

  def one_current_per_scope
    taken = self.class.current.where(workspace_id: workspace_id, scope_type: scope_type, scope_id: scope_id).where.not(id: id).exists?
    errors.add(:base, taken_message) if taken
  end
end
