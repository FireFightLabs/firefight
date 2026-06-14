module Entitlements
  AI = "ai"

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

  def self.allow
    Result.new(true, nil)
  end

  def self.deny(message)
    Result.new(false, message)
  end
end
