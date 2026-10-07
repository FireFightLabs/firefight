module FeatureFlags
  class UnknownFlag < ArgumentError; end

  # Sign in with ChatGPT as a workspace's AI account, until OpenAI approves its use here.
  CHATGPT_SIGN_IN = :chatgpt_sign_in
  # Google and email on the sign-in page. Global, since nobody signing in has a workspace yet.
  SELF_SERVE_SIGNUP = :self_serve_signup

  WORKSPACE = [ CHATGPT_SIGN_IN ].freeze
  GLOBAL = [ SELF_SERVE_SIGNUP ].freeze
  ALL = (WORKSPACE + GLOBAL).freeze

  def self.enabled?(workspace, flag)
    Flipper.enabled?(known!(flag, WORKSPACE), workspace)
  end

  def self.enable!(workspace, flag)
    Flipper.enable_actor(known!(flag, WORKSPACE), workspace)
  end

  def self.disable!(workspace, flag)
    Flipper.disable_actor(known!(flag, WORKSPACE), workspace)
  end

  def self.enabled_globally?(flag)
    Flipper.enabled?(known!(flag, GLOBAL))
  end

  def self.enable_globally!(flag)
    Flipper.enable(known!(flag, GLOBAL))
  end

  def self.disable_globally!(flag)
    Flipper.disable(known!(flag, GLOBAL))
  end

  def self.global?(flag) = GLOBAL.include?(flag.to_s.to_sym)

  def self.workspaces_with(flag)
    prefix = "#{Workspace.name};"
    ids = Flipper.feature(known!(flag, WORKSPACE)).actors_value.filter_map do |flipper_id|
      flipper_id.delete_prefix(prefix) if flipper_id.start_with?(prefix)
    end
    Workspace.where(id: ids)
  end

  def self.known!(flag, scope)
    name = flag.to_s.to_sym
    raise UnknownFlag, "Unknown feature flag #{flag.inspect}" unless ALL.include?(name)
    raise UnknownFlag, "#{flag} is #{global?(name) ? 'a global flag' : 'set per workspace'}" unless scope.include?(name)

    name
  end
  private_class_method :known!
end
