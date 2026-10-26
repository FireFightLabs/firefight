# What incidents taught that a review checks the change against: the approved lessons, those about the services that
# own the repository and what they run on first. A finding a lesson produced names it, and one from a strict lesson
# fails a check on the pull request until it is fixed or a person overrides it.
module PullRequestReview::Lessons
  extend ActiveSupport::Concern

  # The services whose repository this is, as the catalog says.
  def owning_services = @owning_services ||= CatalogEntry.owning_repository(workspace, repository)

  # What the change touches: the owning services, the resources they run on, and the repository on the map.
  def touched_subjects
    services = owning_services
    resources = ResourceMap::Resource.present.where(workspace: workspace)
    linked = services.any? ? resources.joins(:entry_links).where(resource_map_entry_links: { catalog_entry_id: services.map(&:id) }).distinct.to_a : []
    repository_resource = resources.where(kind: ResourceMap::KIND_REPOSITORY).where("lower(external_id) = ?", repository.downcase).to_a
    services + linked + repository_resource
  end

  def lessons_to_check = @lessons_to_check ||= Chat::Memory.for_review(workspace, touched_subjects)

  # The lessons as the review reads them, one a line: its id, where it came from, whether it is strict, and what it says.
  def lesson_lines
    lessons_to_check.map do |lesson|
      "#{lesson.id} (lesson from #{lesson.source.identifier}#{", about #{lesson.about}" if lesson.about}#{', strict' if lesson.strict}): #{lesson.text}"
    end
  end

  # The lesson a finding cites by id, only when it is one this review was handed, so a model cannot tie a finding to any
  # other memory.
  def lesson_cited(id) = lessons_to_check.find { |lesson| lesson.id == id.to_s }
end
