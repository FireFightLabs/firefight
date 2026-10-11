# What changed around something failing, as candidates to check before Halon's first model call: deploys, settings,
# links that came or went and changes made through Firefight on the failing resources and their neighbours up to two
# hops, and the alerts on them, all within the window, nearest to when the trouble began first. Firefight's own code
# builds it from the map, what changed (ResourceMap::Timeline) and the alerts, so it costs no model call and a run reads
# the same list each time. It names candidates, never a cause.
class ResourceMap::Suspects
  HOPS = 2
  SHOWN = 8
  # Before the trouble began, where the change behind it usually is.
  LEAD = 2.hours
  # The kinds of change that can cause trouble. A status change is a symptom, not a suspect.
  KINDS = [
    ResourceMap::Timeline::KIND_DEPLOY, ResourceMap::Timeline::KIND_CONFIG, ResourceMap::Timeline::KIND_APPEARED, ResourceMap::Timeline::KIND_REMOVED,
    ResourceMap::Timeline::KIND_RENAMED, ResourceMap::Timeline::KIND_REPORTED, ResourceMap::Timeline::KIND_FIREFIGHT
  ].freeze
  LEAD_WORDS = "Suspects Firefight found on the map before you started, nearest to when the trouble began first. Each is a " \
               "candidate to check, never a conclusion:".freeze

  Suspect = Data.define(:at, :what, :where, :hop, :link) do
    def line
      near = hop.zero? ? "on #{where}" : "on #{where}, #{hop == 1 ? '1 hop' : "#{hop} hops"} from what is failing"
      "- #{at.utc.iso8601} #{what} (#{near})#{" #{link}" if link}"
    end
  end

  # roots are the failing resources, anchor when the trouble began, and the window runs from from to to.
  def initialize(workspace:, principal:, roots:, anchor:, from:, to: Time.current)
    @workspace = workspace
    @principal = principal
    @roots = roots
    @anchor = anchor
    @from = from
    @to = to
  end

  def list
    @list ||= (changes + alerts).sort_by { |suspect| [ (suspect.at - @anchor).abs, suspect.hop ] }.first(SHOWN)
  end

  def text = list.empty? ? nil : [ LEAD_WORDS, *list.map(&:line) ].join("\n")

  # The resources the person's words name on the map, by a whole word, for a chat that is not in an incident.
  def self.named_in(workspace, principal, words, limit: 3)
    text = words.to_s.downcase
    return [] if text.blank?

    ResourceMap::Resource.visible_to(principal, workspace).present.where("length(resource_map_resources.name) >= 3").to_a
                         .select { |resource| text.match?(/(?<![\w-])#{Regexp.escape(resource.name.downcase)}(?![\w-])/) }.first(limit)
  end

  private

  def hops
    @hops ||= @roots.each_with_object({}) do |root, found|
      found[root.id] = 0
      root.neighborhood(depth: HOPS).each do |link, hop|
        next if ResourceMap::OWNING_RELATIONS.include?(link.relation)

        [ link.from_resource_id, link.to_resource_id ].each { |id| found[id] = [ found[id] || hop, hop ].min }
      end
    end
  end

  def resources = @resources ||= ResourceMap::Resource.visible_to(@principal, @workspace).present.where(id: hops.keys).to_a

  def changes
    subject = ResourceMap::Timeline::Subject.new(kind: ResourceMap::Timeline::SUBJECT_SERVICE, name: nil, resources: resources)
    ResourceMap::Timeline.new(workspace: @workspace, principal: @principal, subject: subject, from: @from, to: @to).entries
                         .select { |entry| KINDS.include?(entry.kind) && entry.resource_id }
                         .map do |entry|
      Suspect.new(at: entry.at, what: "#{ResourceMap::Timeline::KIND_LABELS.fetch(entry.kind)}: #{entry.what}", where: entry.where,
                  hop: hops.fetch(entry.resource_id, HOPS), link: entry.link)
    end
  end

  # Alerts in the window whose title names one of the resources.
  def alerts
    named = resources.index_by { |resource| resource.name.downcase }
    return [] if named.empty?

    @workspace.alerts.where(received_at: @from..@to).includes(:alert_source).order(received_at: :desc).limit(200).filter_map do |alert|
      title = alert.title.to_s.downcase
      hit = named.find { |name, _resource| title.match?(/(?<![\w-])#{Regexp.escape(name)}(?![\w-])/) }
      next unless hit

      Suspect.new(at: alert.received_at, what: "Alert: #{alert.title}", where: hit.last.scoped_name, hop: hops.fetch(hit.last.id, HOPS), link: alert.source_url)
    end
  end
end
