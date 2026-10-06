# Test providers that say what changed on the map, so live updates are tested without reaching one. Each is a provider
# definition like any in app/services/integrations/providers, keyed so no registry entry shares it.
#
# livetest  is set up by hand and signs each delivery with an HMAC of its body. Its pack reads one scope again from
#           LiveTestPack.world, the provider's current state, unless LiveTestPack.narrows is false.
# livepoll  keeps a change log Firefight reads (LiveTestPoll.log).
# livehook  is registered with by Firefight itself, and its webhooks lapse.
# liveapp   sends every connection's changes to one address for its app.

class LiveTestPack < Integrations::NativePack
  ACCOUNT = "acme".freeze

  class << self
    # The provider's current state, by [kind, name], and whether a read can be narrowed to one scope.
    attr_accessor :world, :narrows, :reads, :refusal

    def reset!
      self.world = {}
      self.narrows = true
      self.reads = []
      self.refusal = nil
    end

    def found(kind, name, status: "running", details: {})
      ResourceMap::Found.new(provider: "livetest", account: ACCOUNT, kind: kind, external_id: name, name: name, status: status, details: details)
    end
  end
  reset!

  def map_of(_row)
    ResourceMap::Snapshot.new(resources: self.class.world.values, links: [])
  end

  def map_refresh(_row, scope)
    self.class.reads << scope
    raise self.class.refusal if self.class.refusal
    return unless self.class.narrows

    key = [ "livetest", scope.account || ACCOUNT, scope.kind, scope.external_id ]
    present = self.class.world.values.select { |found| scope.covers?(found.key) }
    links = present.flat_map { |found| Array(found.details["uses"]).map { |to| ResourceMap::FoundLink.new(from: found.key, to: [ "livetest", ACCOUNT, ResourceMap::KIND_DATABASE, to ], relation: ResourceMap::RELATION_USES) } }
    ResourceMap::Snapshot.new(resources: present, links: links, gone: present.empty? && scope.external_id ? [ key ] : [])
  end
end

class LiveTestEvents < Integrations::MapEventSource
  SIGNATURE = "X-Live-Signature".freeze

  class << self
    def verify(raw_body:, headers:, secret:)
      ActiveSupport::SecurityUtils.secure_compare(headers[SIGNATURE].to_s, OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, raw_body))
    end

    def events(payload, headers:)
      Array(payload["changes"]).map do |change|
        scope = change["kind"] ? ResourceMap::Scope.new(account: LiveTestPack::ACCOUNT, kind: change["kind"], external_id: change["name"]) : ResourceMap::Scope.everything
        ResourceMap::Event.new(id: change["id"], at: Time.iso8601(change["at"]), action: change["action"], scope: scope)
      end
    end

    def setup_steps = [ "Open the webhook settings in Live test.", "Add a webhook to the address above, then copy its signing secret here." ]
  end
end

class LiveTestPoll < Integrations::MapEventSource
  class << self
    attr_accessor :log

    def verify(**) = false

    def events(_payload, headers:) = []

    # The log holds [cursor, event] pairs in order, and a read answers those after since.
    def poll(_row, since:)
      after = log.select { |cursor, _event| since.nil? || cursor > since }
      Integrations::MapEventSource::Polled.new(events: after.map(&:last), cursor: after.last&.first || since)
    end
  end
  self.log = []
end

class LiveTestHook < LiveTestEvents
  class << self
    # failure is a reason registering fails with, refusal one the provider gives for its plan or a limit, and asking what
    # registering would cost the account, for a person to decide.
    attr_accessor :registered, :removed, :failure, :refusal, :asking

    def setup_steps = []

    def confirmation_for(_row, url:) = asking

    def register(_row, url:)
      raise Integrations::Error, failure if failure
      raise Integrations::MapEventSource::Refused, refusal if refusal

      self.registered = url
      Integrations::MapEventSource::Webhook.new(id: "hook-1", secret: "registered-secret", expires_at: 2.days.from_now)
    end

    def refresh(_row, _webhook_id) = 30.days.from_now

    def remove(_row, webhook_id)
      self.removed = webhook_id
    end
  end
end

class LiveTestApp < LiveTestEvents
  class << self
    def setup_steps = []

    def installation_of(payload, headers:) = payload.dig("installation", "id")
  end
end

module Integrations
  module Providers
    Livetest = Provider.new(key: "livetest", pack: "LiveTestPack", map_events: "LiveTestEvents") unless const_defined?(:Livetest, false)
    Livepoll = Provider.new(key: "livepoll", pack: "LiveTestPack", map_events: "LiveTestPoll") unless const_defined?(:Livepoll, false)
    Livehook = Provider.new(key: "livehook", pack: "LiveTestPack", map_events: "LiveTestHook") unless const_defined?(:Livehook, false)
    Liveapp = Provider.new(key: "liveapp", pack: "LiveTestPack", map_events: "LiveTestApp") unless const_defined?(:Liveapp, false)
  end
end

module LiveUpdatesTestHelper
  def connect_live!(workspace, provider: "livetest", name: "Live test", slug: provider)
    integration = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: name, slug: slug)
    integration.integration_environments.create!
  end

  def with_app_host(host = "firefight.example.com")
    previous = ENV["APP_HOST"]
    ENV["APP_HOST"] = host
    yield
  ensure
    ENV["APP_HOST"] = previous
  end

  def live_delivery(changes, secret:)
    body = { "changes" => changes }.to_json
    [ body, { LiveTestEvents::SIGNATURE => OpenSSL::HMAC.hexdigest("SHA256", secret, body), "Content-Type" => "application/json" } ]
  end

  def change(id, at:, kind: ResourceMap::KIND_SERVICE, name: "web", action: ResourceMap::Event::UPDATED)
    { "id" => id, "at" => at.utc.iso8601(6), "kind" => kind, "name" => name, "action" => action }
  end

  def event(id, at:, kind: ResourceMap::KIND_SERVICE, name: "web", action: ResourceMap::Event::UPDATED)
    ResourceMap::Event.new(id: id, at: at, action: action, scope: ResourceMap::Scope.new(account: LiveTestPack::ACCOUNT, kind: kind, external_id: name))
  end
end
