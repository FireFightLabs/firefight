# One thing that changed around a resource, for its panel on the map (ResourceMap::Timeline).
class ResourceMapTimelineEntrySerializer < BaseSerializer
  object_as :entry

  # Made from when and what, since an entry is read rather than stored.
  type :string
  def id = Digest::SHA256.hexdigest([ entry.at.utc.iso8601(6), entry.kind, entry.what ].join("|")).first(16)

  type :string
  def at = entry.at.utc.iso8601

  type "ResourceMapTimelineKind"
  def kind = entry.kind

  type :string
  def label = ResourceMap::Timeline::KIND_LABELS.fetch(entry.kind)

  type "ResourceMapTimelineSource"
  def source = entry.source

  type :string
  def what = entry.what

  # Who made it, when Firefight knows.
  type :string, optional: true
  def by = entry.by

  # The page it came from.
  type :string, optional: true
  def link = entry.link
end
