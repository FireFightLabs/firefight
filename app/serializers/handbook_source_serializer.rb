# Where synced handbook pages come from, with when it was last read and what went wrong, as the Handbook page lists it.
class HandbookSourceSerializer < BaseSerializer
  object_as :source

  type :string
  def id = source.id

  type "'repository' | 'document'"
  def kind = source.kind

  # Such as "docs/ in acme/web".
  type :string
  def label = source.label

  type :string, optional: true
  def url = source.url

  type :string, optional: true
  def connection = source.integration&.name

  type :number
  def page_count = source.pages.size

  type :string, optional: true
  def synced_at = source.synced_at&.utc&.iso8601

  # Why the last read failed, or what it left out.
  type :string, optional: true
  def sync_error = source.sync_error
end
