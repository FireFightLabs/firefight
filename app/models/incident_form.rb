class IncidentForm < ApplicationRecord
  SLUG_DECLARE = "declare"
  SLUG_UPDATE = "update"
  SLUG_RESOLVE = "resolve"
  SLUG_CANCEL = "cancel"
  SLUGS = [ SLUG_DECLARE, SLUG_UPDATE, SLUG_RESOLVE, SLUG_CANCEL ].freeze

  # Built-in lifecycle forms the system dispatches on. Workspaces never need
  # these seeded. With no DB row, defaults from this constant apply.
  # A DB row only needs to exist when an admin customizes the form (renames
  # it, reorders, adds a custom field). See `Workspace#ensure_incident_form!`.
  DEFAULTS = [
    { slug: SLUG_DECLARE, name: "Declare", description: "Shown when a responder first declares an incident.", lifecycle_event: SLUG_DECLARE, position: 1 },
    { slug: SLUG_UPDATE,  name: "Update",  description: "Shown when responders share a status update.",       lifecycle_event: SLUG_UPDATE,  position: 2 },
    { slug: SLUG_RESOLVE, name: "Resolve", description: "Shown when the incident is resolved or closed.",     lifecycle_event: SLUG_RESOLVE, position: 3 },
    # No system fields by default. Nothing is asked when an incident turns out
    # not to be one, unless a workspace attaches something worth asking.
    { slug: SLUG_CANCEL,  name: "Cancel",  description: "Shown when an incident is canceled as not a real incident.", lifecycle_event: SLUG_CANCEL, position: 4 }
  ].freeze

  DEFAULTS_BY_SLUG = DEFAULTS.index_by { |d| d[:slug] }.freeze

  # Which forms could already have been answered by the time this one opens, and
  # so whose custom fields a condition here may read. Declare always ran. Update
  # may have run any number of times. Cancel replaces Resolve rather than
  # following it, so neither can see the other's answers.
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

  # Returns the merged set of all forms for a workspace. Code-default forms
  # for slugs that have no DB row (unpersisted instances), plus any
  # persisted DB rows (which override the default name/description/position).
  def self.all_for_workspace(workspace)
    persisted = workspace.incident_forms.to_a.index_by(&:slug)
    DEFAULTS.map do |defaults|
      persisted[defaults[:slug]] || new(workspace: workspace, **defaults)
    end.sort_by(&:position)
  end

  def self.defaults_for(slug)
    DEFAULTS_BY_SLUG[slug]
  end

  # Code-defaults merged with DB overlay rows. Used by the settings editor
  # so it shows every field that will actually appear in Slack (including
  # the code-driven system fields that have no DB row).
  def resolved_fields(include_hidden: false)
    IncidentFormResolver.new(workspace).resolve(
      lifecycle_event, include_hidden: include_hidden, form: (self if persisted?)
    )
  end

  # Everything a condition on this form may read. What this form and the forms
  # before it actually ask a responder for. Mirroring the form is what stops the
  # picker offering a rule whose answer nobody is ever asked to give, and what
  # makes hiding a field remove it as a source.
  #
  # Conditions are ignored when working this out. A field that is itself
  # conditional is still asked for, just not always.
  def condition_source_definitions
    slugs = CONDITION_SOURCE_SLUGS.fetch(lifecycle_event, [ lifecycle_event ])
    resolver = IncidentFormResolver.new(workspace)

    definitions = slugs.flat_map { |slug| asked_fields(resolver, slug) }
      .filter_map(&:incident_field_definition)
      .select { |definition| IncidentCondition::SUPPORTED_CUSTOM_FIELD_TYPES.include?(definition.field_type) }

    definitions.uniq(&:id).sort_by { |definition| [ definition.position, definition.created_at ] }
  end

  # System fields this form asks for that a condition can read. Only the ones a
  # responder picks from a set, a condition on free text has nothing to match.
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

  # What a form puts in front of a responder, before conditions narrow it.
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
