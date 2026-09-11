module FeatureFlags
  class UnknownFlag < ArgumentError; end

  AI_SRE = :ai_sre

  ALL = [ AI_SRE ].freeze

  def self.enabled?(workspace, flag)
    Flipper.enabled?(known!(flag), workspace)
  end

  def self.enable!(workspace, flag)
    Flipper.enable_actor(known!(flag), workspace)
  end

  def self.disable!(workspace, flag)
    Flipper.disable_actor(known!(flag), workspace)
  end

  def self.workspaces_with(flag)
    prefix = "#{Workspace.name};"
    ids = Flipper.feature(known!(flag)).actors_value.filter_map do |flipper_id|
      flipper_id.delete_prefix(prefix) if flipper_id.start_with?(prefix)
    end
    Workspace.where(id: ids)
  end

  def self.known!(flag)
    name = flag.to_s.to_sym
    raise UnknownFlag, "Unknown feature flag #{flag.inspect}" unless ALL.include?(name)

    name
  end
  private_class_method :known!
end
