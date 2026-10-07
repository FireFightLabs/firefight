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

  # Firefight's own workspaces run on Firefight's key and are never billed for it. Only a hosted build asks, and one
  # that has not said keeps every workspace on Firefight's key, as before workspaces could bring their own.
  def self.firefight_pays_for_ai?(workspace)
    return false if ai_account(workspace) == AI_ACCOUNT_OPERATOR
    return true unless backend.respond_to?(:firefight_pays_for_ai?)

    backend.firefight_pays_for_ai?(workspace)
  end

  # The workspace's Firefight credit balance on a hosted build, responding to spendable? (it can pay for a call), used?
  # (it held credit and has none left) and summary ({ title:, detail: } for the row under the workspace's own AI
  # accounts). Nil where credits are not sold, which is every install someone runs themselves.
  def self.ai_credit(workspace) = backend.try(:ai_credit, workspace)

  # Whether an AI account may point at a private or loopback address, such as an Ollama on the same machine. An install
  # someone runs themselves may, since the network is theirs. A hosted build may not unless its backend says so, since
  # the address would be inside Firefight's network.
  def self.private_ai_endpoints?(workspace)
    return backend.private_ai_endpoints?(workspace) if backend.respond_to?(:private_ai_endpoints?)

    ai_account(workspace) == AI_ACCOUNT_OPERATOR
  end

  # A model call paid with Firefight credits, for the backend to charge. Answers what it billed in micros, or nil when
  # nothing is charged, which is every install someone runs themselves.
  def self.charge_ai!(inference)
    billed = backend.try(:charge_ai!, inference)
    billed.is_a?(Integer) ? billed : nil
  end

  def self.allow
    Result.new(true, nil)
  end

  def self.deny(message)
    Result.new(false, message)
  end
end
