# Something a memory or instructions can be about, as the Memory page's picker offers it.
class MemorySubjectOptionSerializer < BaseSerializer
  object_as :subject

  type :string
  def value = Chat::Memory.subject_key(subject)

  # Such as "Checkout · Service" or "web · Acme Cloud".
  type :string
  def label
    case subject
    when CatalogEntry then "#{subject.name} · #{subject.catalog_type.name}"
    else "#{subject.name} · #{ResourceMap.provider_name(subject.provider)}"
    end
  end
end
