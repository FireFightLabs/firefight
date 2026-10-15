module FeatureFlags
  class UnknownFlag < ArgumentError; end

  # Sign in with ChatGPT as a workspace's AI account, until OpenAI approves its use here.
  CHATGPT_SIGN_IN = :chatgpt_sign_in
  # Workflows a workspace builds and runs, until the whole feature ships. No run of one starts, waits out its time or
  # carries on without it, and every page, Halon tool and MCP tool for them asks it too.
  WORKFLOWS = :workflows
  # A workspace's own skills, which Halon loads beside Firefight's, with their page, Halon's proposals and their tools.
  # A workflow that runs one still needs WORKFLOWS for the workflow side.
  CUSTOM_SKILLS = :custom_skills
  # Google and email on the sign-in page. Global, since nobody signing in has a workspace yet.
  SELF_SERVE_SIGNUP = :self_serve_signup

  WORKSPACE = [ CHATGPT_SIGN_IN, WORKFLOWS, CUSTOM_SKILLS ].freeze
  GLOBAL = [ SELF_SERVE_SIGNUP ].freeze
  ALL = (WORKSPACE + GLOBAL).freeze

  def self.enabled?(workspace, flag)
    Flipper.enabled?(known!(flag, WORKSPACE), workspace)
  end

  # Turning workflows on moves what each runbook runs into a workflow, so nothing runs two ways at once.
  def self.enable!(workspace, flag)
    name = known!(flag, WORKSPACE)
    Flipper.enable_actor(name, workspace)
    Runbook.move_runnable_parts!(workspace) if name == WORKFLOWS
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

  # Reads each flag once while the block runs, for work that checks the same flags again and again and has no request to
  # memoize them, such as a reply. Flipper's instance is the fiber's own, so nothing else running in the process is
  # affected. Left as it was when something already memoizes.
  def self.memoized
    already = Flipper.memoizing?
    Flipper.memoize = true unless already
    yield
  ensure
    Flipper.memoize = false unless already
  end

  def self.known!(flag, scope)
    name = flag.to_s.to_sym
    raise UnknownFlag, "Unknown feature flag #{flag.inspect}" unless ALL.include?(name)
    raise UnknownFlag, "#{flag} is #{global?(name) ? 'a global flag' : 'set per workspace'}" unless scope.include?(name)

    name
  end
  private_class_method :known!
end
