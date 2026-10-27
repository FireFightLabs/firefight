# What incidents taught that a review checks the change against: the approved lessons the reviewer may read, those
# about the services that own the repository and what they run on first. A finding a lesson produced names it, and one
# from a strict lesson fails a check on the pull request until it is fixed or a person overrides it.
module PullRequestReview::Lessons
  extend ActiveSupport::Concern

  # The services whose repository this is, as the catalog says.
  def owning_services = @owning_services ||= CatalogEntry.owning_repository(workspace, repository)

  # The members who own the services the repository belongs to: each service's own members and manager, and those of
  # the teams that own it, as the catalog names them.
  def service_owner_ids
    @service_owner_ids ||= owning_services.flat_map { |service| [ service, *service.owning_teams ] }.uniq.flat_map do |entry|
      [ *Array(entry.role_value(CatalogAttributeDefinition::ROLE_MEMBERS)), entry.role_value(CatalogAttributeDefinition::ROLE_MANAGER) ]
    end.compact_blank.map(&:to_s).uniq
  end

  def owned_by?(member) = member.is_a?(WorkspaceMembership) && service_owner_ids.include?(member.id.to_s)

  # What the change touches: the owning services, the resources they run on, and the repository on the map.
  def touched_subjects
    services = owning_services
    resources = ResourceMap::Resource.present.where(workspace: workspace)
    linked = services.any? ? resources.joins(:entry_links).where(resource_map_entry_links: { catalog_entry_id: services.map(&:id) }).distinct.to_a : []
    repository_resource = resources.where(kind: ResourceMap::KIND_REPOSITORY).where("lower(external_id) = ?", repository.downcase).to_a
    services + linked + repository_resource
  end

  # The approved lessons principal may read, so one about a resource outside its map reach is never handed over.
  def lessons_to_check(principal)
    @lessons_to_check ||= {}
    @lessons_to_check[principal] ||= begin
      approved = Chat::Memory.for_review(workspace, touched_subjects)
      visible = Chat::Memory.visible_to(principal, workspace).where(id: approved.map(&:id)).pluck(:id).to_set
      approved.select { |lesson| visible.include?(lesson.id) }
    end
  end

  # The lessons as the review reads them, one a line: its id, where it came from, whether it is strict, and what it says.
  def lesson_lines(principal)
    lessons_to_check(principal).map do |lesson|
      "- #{lesson.id} (lesson from #{lesson.lesson_origin}#{", about #{lesson.about}" if lesson.about}#{', strict' if lesson.strict}): #{lesson.text}"
    end
  end

  # The lesson a finding cites by id, only when it is one this review was handed, so a model cannot tie a finding to any
  # other memory.
  def lesson_cited(id, principal) = lessons_to_check(principal).find { |lesson| lesson.id == id.to_s.strip }
end
