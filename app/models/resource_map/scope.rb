module ResourceMap
  # What a change event asks Firefight to read again, within the connection that sent it: one resource (its kind and id,
  # and its account when the id alone is not unique), every resource of a kind in an account, or an account. A scope
  # naming nothing is everything the connection reaches, which only a full sweep reads.
  Scope = Data.define(:account, :kind, :external_id) do
    def initialize(account: nil, kind: nil, external_id: nil)
      super(account: account.presence&.to_s, kind: kind.presence&.to_s, external_id: external_id.presence&.to_s)
    end

    def everything? = to_h.values.none?

    # Whether a resource's key ([provider, account, kind, external_id]) lies within it.
    def covers?(key)
      _provider, key_account, key_kind, key_id = key
      [ [ account, key_account ], [ kind, key_kind ], [ external_id, key_id ] ].all? { |asked, given| asked.nil? || asked == given.to_s }
    end

    # The same scope is the same key, so events about it are read again together.
    def key = everything? ? "everything" : Digest::SHA256.hexdigest(to_job.sort.to_json).first(32)

    def to_job = to_h.compact.transform_keys(&:to_s)

    def self.from_job(hash) = new(**hash.to_h.symbolize_keys.slice(:account, :kind, :external_id))

    def self.everything = new
  end
end
