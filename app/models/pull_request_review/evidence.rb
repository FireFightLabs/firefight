# What of a review's evidence a viewer may see. A resource on the map is shown only to someone whose map reach holds it,
# the same as the map itself. An incident, a postmortem, a metric's page and the code are what any member reads already.
module PullRequestReview::Evidence
  module_function

  # The resource ids among findings' evidence the principal may read, from each map link's resource.
  def reachable(findings, principal)
    ids = findings.flat_map(&:evidence_items).select { |item| item.kind == PullRequestReview::Finding::EVIDENCE_MAP_RESOURCE }.filter_map { |item| resource_of(item.url) }
    return Set.new if ids.empty? || findings.empty?

    ResourceMap::Resource.visible_to(principal, findings.first.review.workspace).where(id: ids.uniq).pluck(:id).to_set
  end

  def shown?(item, reachable)
    item.kind != PullRequestReview::Finding::EVIDENCE_MAP_RESOURCE || reachable.include?(resource_of(item.url))
  end

  def resource_of(url)
    query = URI.parse(url.to_s).query
    query && Rack::Utils.parse_query(query)[ResourceMap::PAGE_RESOURCE_PARAM].presence
  rescue URI::InvalidURIError
    nil
  end
end
