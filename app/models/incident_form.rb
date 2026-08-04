class IncidentForm < ApplicationRecord
  SLUG_DECLARE = "declare"
  SLUG_UPDATE = "update"
  SLUG_RESOLVE = "resolve"
  SLUG_CANCEL = "cancel"
  SLUGS = [ SLUG_DECLARE, SLUG_UPDATE, SLUG_RESOLVE, SLUG_CANCEL ].freeze

  # Built-in lifecycle forms the system dispatches on. Workspaces never need
  # these seeded — if no DB row exists, defaults from this constant apply.
  # A DB row only needs to exist when an admin customizes the form (renames
  # it, reorders, adds a custom field) — see `Workspace#ensure_incident_form!`.
  DEFAULTS = [
    { slug: SLUG_DECLARE, name: "Declare", description: "Shown when a responder first declares an incident.", lifecycle_event: SLUG_DECLARE, position: 1 },
    { slug: SLUG_UPDATE,  name: "Update",  description: "Shown when responders share a status update.",       lifecycle_event: SLUG_UPDATE,  position: 2 },
    { slug: SLUG_RESOLVE, name: "Resolve", description: "Shown when the incident is resolved or closed.",     lifecycle_event: SLUG_RESOLVE, position: 3 },
    # No system fields by default. Nothing is asked when an incident turns out
    # not to be one, unless a workspace attaches something worth asking.
    { slug: SLUG_CANCEL,  name: "Cancel",  description: "Shown when an incident is canceled as not a real incident.", lifecycle_event: SLUG_CANCEL, position: 4 }
  ].freeze

  DEFAULTS_BY_SLUG = DEFAULTS.index_by { |d| d[:slug] }.freeze

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

  # Returns the merged set of all forms for a workspace: code-default forms
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

  def default_form?
    !persisted?
  end

  private

  def slug_immutable
    return unless slug_changed?

    errors.add(:slug, "cannot be changed after creation")
  end
end
