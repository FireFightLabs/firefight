module Entitlements
  AI = "ai"
  # Whether the workspace may be used at all. A hosted build answers with its plan, an install someone runs always allows.
  ACCESS = "access"

  # Whose account pays for the AI a workspace uses. On Firefight's own cloud it is Firefight's, on an install someone
  # runs themselves it is theirs, since the model keys are their own.
  AI_ACCOUNT_FIREFIGHT = "firefight"
  AI_ACCOUNT_OPERATOR = "operator"

  def self.backend
    @backend ||= OpenSourceBackend.new
  end

  def self.backend=(backend)
    @backend = backend
  end

  def self.reset_backend!
    @backend = OpenSourceBackend.new
  end

  def self.check(workspace, feature)
    backend.check(workspace, feature)
  end

  def self.allows?(workspace, feature)
    check(workspace, feature).allowed?
  end

  # Asked of the backend, which knows where it runs. One that does not say is a hosted build, since only the open-source
  # backend runs on an operator's own keys.
  def self.ai_account(workspace)
    backend.try(:ai_account, workspace) || AI_ACCOUNT_FIREFIGHT
  end

  # Where a new workspace goes once it is created, such as choosing a plan. Nil sends it on to the dashboard.
  def self.next_step_path(workspace)
    backend.try(:next_step_path, workspace)
  end

  # Run daily, for a backend that keeps time based state such as retention. The open-source backend has none.
  def self.sweep! = backend.try(:sweep!)

  def self.allow
    Result.new(true, nil, nil)
  end

  def self.deny(message, path: nil)
    Result.new(false, message, path)
  end
end
