module ResourceMap
  # A provider saying something on the map changed, read from a webhook delivery or its change log. Firefight never
  # takes its contents as the truth. It is a nudge to read the scope again, so a duplicate or an event out of order
  # changes nothing the re-read would not. id is the provider's own id for it, which makes a second delivery a no-op,
  # and at is when the provider says it happened, the time the change is recorded at.
  #
  # action says what kind of change it was. rescope is the connection's reach changing, such as repositories removed from an
  # app's installation, which only a full sweep reads.
  Event = Data.define(:id, :at, :action, :scope) do
    def initialize(id:, at:, action:, scope: Scope.everything)
      action = action.to_s
      raise ArgumentError, "a map event's action is one of #{ResourceMap::Event::ACTIONS.join(', ')}, not #{action.inspect}" unless ResourceMap::Event::ACTIONS.include?(action)
      raise ArgumentError, "a map event says when it happened" unless at.respond_to?(:to_time)

      super(id: id.presence&.to_s, at: at.to_time, action: action, scope: scope)
    end

    def rescope? = action == ResourceMap::Event::RESCOPE

    # The provider's id, or one made from what the event says when it gives none, so the same event is still once.
    def provider_id = id || Digest::SHA256.hexdigest([ action, scope.to_job.sort, at.utc.iso8601(6) ].to_json)
  end

  class Event
    ADDED = "added".freeze
    UPDATED = "updated".freeze
    REMOVED = "removed".freeze
    LINKED = "linked".freeze
    RESCOPE = "rescope".freeze
    ACTIONS = [ ADDED, UPDATED, REMOVED, LINKED, RESCOPE ].freeze
  end
end
