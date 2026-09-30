# One resource on the map page, with what the catalog says about it and what depends on it.
class ResourceMapResourceSerializer < BaseSerializer
  object_as :row

  type :string
  def id = row.resource.id

  type :string
  def name = row.resource.name

  type "ResourceMapKind"
  def kind = row.resource.kind

  type :string
  def provider = row.resource.provider

  type :string
  def provider_name = ResourceMap.provider_name(row.resource.provider)

  type :string, optional: true
  def provider_mark = ResourceMap.provider_entry(row.resource.provider)&.mark

  type :string, optional: true
  def provider_color = ResourceMap.provider_entry(row.resource.provider)&.color

  type :string
  def account = row.resource.account

  type :string
  def external_id = row.resource.external_id

  type :string, optional: true
  def environment = row.resource.integration_environment&.environment&.name

  type :string, optional: true
  def status = row.resource.status

  type :string, optional: true
  def status_label = row.resource.status_label

  type "ResourceMapHealth"
  def health = row.resource.health

  type :string, optional: true
  def url = row.resource.url

  # What the provider reported, as label and value pairs a person reads.
  type "string[][]"
  def facts = ResourceMap.facts(row.resource.details)

  type :string
  def first_seen_at = row.resource.first_seen_at.utc.iso8601

  type :string
  def last_seen_at = row.resource.last_seen_at.utc.iso8601

  type :number
  def recent_incident_count = row.recent_incident_count

  # Every resource that stops if this one fails, directly or through others.
  type "string[]"
  def dependent_ids = row.dependent_ids

  # Resources that would also stop if the suggested links, which no one has confirmed, are right.
  type "string[]"
  def suggested_dependent_ids = row.suggested_dependent_ids

  # What the workspace remembers about it or the catalog entries it runs, as [id, state, text].
  type "string[][]"
  def memories = row.memories.map { |memory| [ memory.id, memory.state, memory.text ] }

  # People's instructions for it or the catalog entries it runs, as [id, where they apply, text].
  type "string[][]"
  def instructions = row.instructions.map { |note| [ note.id, note.label, note.text ] }

  has_many :baselines, serializer: ResourceMapBaselineSerializer do
    row.baselines
  end

  has_many :entries, as: :catalog_entries, serializer: ResourceMapEntrySerializer do
    row.entries
  end

  has_many :open_incidents, serializer: ResourceMapIncidentSerializer do
    row.open_incidents
  end

  has_many :past_incidents, serializer: ResourceMapPastIncidentSerializer do
    row.past_incidents
  end

  has_one :last_change, serializer: ResourceMapChangeSerializer, optional: true do
    row.last_change
  end
end
