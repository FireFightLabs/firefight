# The outside systems a workspace's apps use that no connection reaches, so Halon can name the one a question needs and
# how to connect it rather than guessing what it did. What says an app uses a system is on the map and in the catalog: a
# service's setting named for it, such as STRIPE_SECRET_KEY, a setting whose address is one of its hosts, compared by
# fingerprint since the map keeps no address (ResourceMap::Fingerprint), or a catalog entry of its name. Only resources
# the principal may read on the map are looked at.
class Upstream::BlindSpots
  # Where a setting's address is reached, for comparing a host by its fingerprint.
  HTTPS_PORT = 443

  # evidence holds sentences saying where the system was seen, and how what would close the gap.
  Spot = Data.define(:entry, :evidence, :how) do
    def to_h = { system: entry.name, category: entry.category, evidence: evidence, how_to_connect: how }
  end

  NONE = "Nothing on the map or in the catalog points at an outside system without a connection. A system the apps call " \
         "with no setting naming it is not seen here, so ask the team when a question needs one.".freeze

  def initialize(workspace, principal, category: nil)
    @workspace = workspace
    @principal = principal
    @category = category.presence
  end

  def spots
    seen = evidence
    candidates.filter_map do |entry|
      found = seen[entry.key]
      next if found.empty? || connected.include?(entry.provider)

      Spot.new(entry: entry, evidence: found.uniq.first(5), how: how(entry))
    end
  end

  private

  def candidates
    @candidates ||= Upstream.all.select { |entry| @category.nil? || entry.category == @category }
  end

  # The providers with a connection that is switched on.
  def connected
    @connected ||= @workspace.integrations.active.pluck(:provider).to_set
  end

  def switched_off
    @switched_off ||= @workspace.integrations.where(deleted_at: nil).where.not(disabled_at: nil).pluck(:provider).to_set
  end

  def evidence
    found = Hash.new { |hash, key| hash[key] = [] }
    settings.each do |use|
      where = use.resource.scoped_name
      Upstream.for_setting(use.variable).each { |entry| found[entry.key] << "#{where}'s setting #{use.variable} is named for it" }
      host, entry = by_fingerprint[use.fingerprint] || by_fingerprint[use.domain_fingerprint]
      found[entry.key] << "#{where}'s setting #{use.variable} points at #{host}" if entry
    end
    names = candidates.to_h { |entry| [ entry.name.downcase, entry ] }
    @workspace.catalog_entries.active.pluck(:name).each do |name|
      entry = names[name.to_s.downcase] || Upstream.named(name)
      found[entry.key] << "The catalog lists #{name}" if entry && candidates.include?(entry)
    end
    found
  end

  def settings
    visible = ResourceMap::Resource.visible_to(@principal, @workspace).present
    ResourceMap::Use.where(workspace: @workspace, resource_id: visible.select(:id)).includes(:resource).order(:variable)
  end

  # Each candidate's hosts by their fingerprint on the workspace's map, as a setting reaching it over https is kept.
  def by_fingerprint
    @by_fingerprint ||= candidates.each_with_object({}) do |entry, found|
      entry.hosts.each { |host| found[ResourceMap::Fingerprint.of(host, HTTPS_PORT, @workspace)] ||= [ host, entry ] }
    end
  end

  def how(entry)
    page = entry.status_page ? " Its status page is #{entry.status_page.url}, which check_status_page reads." : ""
    return "#{entry.name} is connected but switched off. An admin switches it on in Integrations, #{integrations_url}.#{page}" if switched_off.include?(entry.provider)
    return "Connect #{entry.name} in Integrations, #{integrations_url(entry.provider)}, so Halon can read it.#{page}" if entry.connectable?

    "Firefight has no connection for #{entry.name}, so Halon cannot read its logs, its settings or what changed there. " \
      "Describe how the team uses it in the catalog, so Halon knows what depends on it.#{page}"
  end

  def integrations_url(provider = nil)
    path = Rails.application.routes.url_helpers.integrations_path(provider ? { Integration::CONNECT_QUERY_PARAM => provider } : {})
    AppUrl.absolute(path)
  end
end
