module Entitlements
  AI = "ai"

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

  def self.allow
    Result.new(true, nil)
  end

  def self.deny(message)
    Result.new(false, message)
  end
end
