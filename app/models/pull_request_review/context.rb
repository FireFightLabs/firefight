# What Firefight already holds about where a pull request's code runs, so a review starts from it rather than looking
# it up: the services the repository runs on the map, what depends on those, and the past incidents and postmortems on
# those services. Reads Firefight's own tables only, within what the reviewer may read on the map, so the same review
# always starts from the same facts. The reviewer reads further with its tools.
class PullRequestReview::Context
  INCIDENTS_SHOWN = 10
  SERVICES_SHOWN = 10

  def initialize(review, principal)
    @review = review
    @principal = principal
  end

  # The repository as the map knows it, or nil when the map does not hold it or the reviewer may not read it.
  def resource
    return @resource if defined?(@resource)

    @resource = ResourceMap::Resource.visible_to(@principal, workspace).present.where(kind: ResourceMap::KIND_REPOSITORY)
                                     .where("lower(external_id) = ?", @review.repository.downcase).order(:created_at).first
  end

  def blast_radius = @blast_radius ||= (ResourceMap::BlastRadius.new(resource) if resource)

  # The services the repository runs and those that depend on it, each once, with who owns it.
  def services = @services ||= blast_radius ? blast_radius.services.first(SERVICES_SHOWN) : []

  # Incidents on those services, newest first, test incidents left out.
  def past_incidents
    @past_incidents ||= begin
      ids = services.map { |service| service.entry.id }
      if ids.empty?
        []
      else
        workspace.incidents.real.where(deleted_at: nil).where(id: IncidentFieldValue.where(catalog_entry_id: ids).select(:incident_id))
                 .includes(:postmortem, :incident_status).recent.limit(INCIDENTS_SHOWN).to_a
      end
    end
  end

  # The facts as sections of the review's first message, each saying plainly when there is nothing.
  def sections
    {
      "Where this repository runs" => where_it_runs,
      "What depends on it" => reach,
      "Past incidents on these services" => incidents,
      "Lessons the team approved" => lessons
    }
  end

  def reach
    return "The map holds nothing that depends on this repository." unless blast_radius && blast_radius.total.positive?

    named = services.map { |service| "- #{service.entry.name}#{" (owned by #{service.owning_teams.map(&:name).to_sentence})" if service.owning_teams.any?}" }
    "#{blast_radius.total} resources on the map depend on it. The services among them:\n#{named.join("\n").presence || '(none named)'}"
  end

  private

  def workspace = @review.workspace

  def where_it_runs
    return "The resource map does not hold #{@review.repository}, so where it runs is not known." unless resource

    "#{@review.repository} is on the resource map as #{resource.name} (resource #{resource.id}). Read its links and blast radius for more."
  end

  # The lessons the team approved, which the review checks the change against, each by its id so a finding can name it.
  def lessons
    lines = @review.lesson_lines(@principal)
    return "The team has approved no lessons yet." if lines.empty?

    "The team approved these lessons, from past incidents and from what people changed on pull requests Halon opened. Check the change against each that applies, and a finding that " \
      "comes from one names its id as lesson. One marked strict fails a check on the pull request until the finding is fixed.\n#{lines.join("\n")}"
  end

  def incidents
    return "No past incidents are recorded on these services." if past_incidents.empty?

    past_incidents.map do |incident|
      postmortem = incident.postmortem ? " Postmortem: #{incident.postmortem.title}." : ""
      "- #{incident.identifier} #{incident.name} (#{incident.incident_status.name}, declared #{incident.declared_at&.to_date}).#{postmortem}"
    end.join("\n")
  end
end
