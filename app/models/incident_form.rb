class IncidentForm < ApplicationRecord
  SLUG_DECLARE = "declare"
  SLUG_UPDATE = "update"
  SLUG_RESOLVE = "resolve"
  SLUG_CANCEL = "cancel"
  SLUGS = [ SLUG_DECLARE, SLUG_UPDATE, SLUG_RESOLVE, SLUG_CANCEL ].freeze

  # A DB row exists only once an admin customizes a form, see
  # Workspace#ensure_incident_form!. Until then these defaults apply.
  DEFAULTS = [
    { slug: SLUG_DECLARE, name: "Declare", description: "Shown when a responder first declares an incident.", lifecycle_event: SLUG_DECLARE, position: 1 },
    { slug: SLUG_UPDATE,  name: "Update",  description: "Shown when responders share a status update.",       lifecycle_event: SLUG_UPDATE,  position: 2 },
    { slug: SLUG_RESOLVE, name: "Resolve", description: "Shown when the incident is resolved or closed.",     lifecycle_event: SLUG_RESOLVE, position: 3 },
    # No system fields by default, nothing is asked when an incident turns out
    # not to be one.
    { slug: SLUG_CANCEL,  name: "Cancel",  description: "Shown when an incident is canceled as not a real incident.", lifecycle_event: SLUG_CANCEL, position: 4 }
  ].freeze

  DEFAULTS_BY_SLUG = DEFAULTS.index_by { |d| d[:slug] }.freeze

  # Which forms a condition here may read answers from. Cancel replaces
  # Resolve rather than following it, so neither sees the other's answers.
  CONDITION_SOURCE_SLUGS = {
    SLUG_DECLARE => [ SLUG_DECLARE ],
    SLUG_UPDATE => [ SLUG_DECLARE, SLUG_UPDATE ],
    SLUG_RESOLVE => [ SLUG_DECLARE, SLUG_UPDATE, SLUG_RESOLVE ],
    SLUG_CANCEL => [ SLUG_DECLARE, SLUG_UPDATE, SLUG_CANCEL ]
  }.freeze

  belongs_to :workspace

  has_many :incident_form_fields, -> { order(:position, :created_at) }, dependent: :destroy

  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :name, presence: true
  validates :lifecycle_event, presence: true, inclusion: { in: SLUGS }
  validates :position, presence: true

  validate :slug_immutable, on: :update

  scope :ordered, -> { order(:position, :created_at) }

  def protected_form?
    SLUGS.include?(slug)
  end

  # Unpersisted defaults for slugs with no DB row, plus the persisted rows.
  def self.all_for_workspace(workspace)
    persisted = workspace.incident_forms.to_a.index_by(&:slug)
    DEFAULTS.map do |defaults|
      persisted[defaults[:slug]] || new(workspace: workspace, **defaults)
    end.sort_by(&:position)
  end

  def self.defaults_for(slug)
    DEFAULTS_BY_SLUG[slug]
  end

  def resolved_fields(include_hidden: false)
    IncidentFormResolver.new(workspace).resolve(
      lifecycle_event, include_hidden: include_hidden, form: (self if persisted?)
    )
  end

  # Mirrors what this form and the ones before it ask, so the picker never offers a rule
  # nobody answers. A conditional field still counts, it is asked, just not always.
  def condition_source_definitions
    slugs = CONDITION_SOURCE_SLUGS.fetch(lifecycle_event, [ lifecycle_event ])
    resolver = IncidentFormResolver.new(workspace)

    definitions = slugs.flat_map { |slug| asked_fields(resolver, slug) }
      .filter_map(&:incident_field_definition)
      .select { |definition| IncidentCondition::SUPPORTED_CUSTOM_FIELD_TYPES.include?(definition.field_type) }

    definitions.uniq(&:id).sort_by { |definition| [ definition.position, definition.created_at ] }
  end

  # Only fields picked from a set, a condition on free text has nothing to match.
  CONDITION_SOURCE_SYSTEM_KEYS = [
    IncidentSystemField::KEY_INCIDENT_TYPE,
    IncidentSystemField::KEY_SEVERITY,
    IncidentSystemField::KEY_STATUS,
    IncidentSystemField::KEY_VISIBILITY
  ].freeze

  def condition_source_system_keys
    slugs = CONDITION_SOURCE_SLUGS.fetch(lifecycle_event, [ lifecycle_event ])
    resolver = IncidentFormResolver.new(workspace)

    slugs.flat_map { |slug| asked_fields(resolver, slug) }
      .filter_map(&:system_field_key)
      .uniq
      .select { |key| CONDITION_SOURCE_SYSTEM_KEYS.include?(key) }
  end

  def default_form?
    !persisted?
  end

  private

  # Before conditions narrow it.
  def asked_fields(resolver, slug)
    resolver.resolve(slug, include_hidden: true).select do |field|
      field.visibility_mode == IncidentFormField::VISIBILITY_MODE_VISIBLE && field.inactive_reason.nil?
    end
  end

  def slug_immutable
    return unless slug_changed?

    errors.add(:slug, "cannot be changed after creation")
  end
end
