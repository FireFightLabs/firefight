# How two resources depend on each other, and how that was found. A sweep owns the links it declared or matched, a
# person or Halon owns the ones they added.
class ResourceMap::Link < ApplicationRecord
  self.table_name = "resource_map_links"

  belongs_to :workspace
  belongs_to :from_resource, class_name: "ResourceMap::Resource", inverse_of: :links_out
  belongs_to :to_resource, class_name: "ResourceMap::Resource", inverse_of: :links_in
  belongs_to :integration_environment, optional: true
  belongs_to :added_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :confirmed_by, class_name: "WorkspaceMembership", optional: true

  # A dismissed suggestion is kept, so the same wrong link is not suggested again, but it is no longer part of the map.
  scope :standing, -> { where(dismissed_at: nil) }
  scope :to_review, -> { standing.where(origin: ResourceMap::ORIGIN_SUGGESTED, confirmed_at: nil) }

  validates :relation, inclusion: { in: ResourceMap::RELATIONS }
  validates :origin, inclusion: { in: ResourceMap::ORIGINS }

  def suggested? = origin == ResourceMap::ORIGIN_SUGGESTED

  def unconfirmed? = suggested? && confirmed_at.nil?

  # A provider's link goes when the provider stops reporting it, so only a person's own link, or a suggestion someone
  # confirmed, is removed by hand. An unconfirmed suggestion is confirmed or dismissed instead.
  def removal_blocked_reason
    case origin
    when ResourceMap::ORIGIN_DECLARED, ResourceMap::ORIGIN_MATCHED
      "#{integration_environment&.integration&.name || 'A connection'} reports this link, so it goes when the connection stops reporting it."
    when ResourceMap::ORIGIN_SUGGESTED
      "Confirm or dismiss this suggestion instead." if confirmed_at.nil?
    end
  end

  # Guarded, so a confirm and a dismiss racing on the same suggestion cannot both land.
  def confirm!(by:)
    decided = self.class.where(id: id, confirmed_at: nil, dismissed_at: nil)
                        .update_all(confirmed_at: Time.current, confirmed_by_id: by&.id, updated_at: Time.current) > 0
    reload
    decided
  end

  # Halon's reading of how two resources depend on each other, with the evidence, held until a person confirms it. A
  # pair already linked, or a suggestion already dismissed, is refused with the reason rather than written twice.
  def self.suggest!(from:, to:, relation:, note:)
    existing = find_by(from_resource: from, to_resource: to, relation: relation)
    return "#{existing.sentence} was dismissed by a person, so it is not suggested again." if existing&.dismissed_at
    return "#{existing.sentence} is already on the map." if existing

    create!(workspace: from.workspace, from_resource: from, to_resource: to, relation: relation, origin: ResourceMap::ORIGIN_SUGGESTED,
            note: note, last_seen_at: Time.current)
  end

  # A link a person knows and no provider reports. Refused with the reason when it would join a resource to itself or
  # repeat a link already on the map.
  def self.add_by_person!(from:, to:, relation:, note:, by:)
    return "A resource cannot depend on itself." if from == to

    existing = find_by(from_resource: from, to_resource: to, relation: relation)
    return "#{existing.sentence} is already on the map." if existing && existing.dismissed_at.nil?

    link = existing || new(workspace: from.workspace, from_resource: from, to_resource: to, relation: relation)
    link.update!(origin: ResourceMap::ORIGIN_PERSON, note: note.presence, added_by: by, dismissed_at: nil, last_seen_at: Time.current)
    link
  end

  def dismiss!
    decided = self.class.where(id: id, confirmed_at: nil, dismissed_at: nil).update_all(dismissed_at: Time.current, updated_at: Time.current) > 0
    reload
    decided
  end

  def sentence = "#{from_resource.name} #{ResourceMap::RELATION_WORDS.fetch(relation)} #{to_resource.name}"
end
