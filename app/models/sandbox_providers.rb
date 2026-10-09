# Where this deployment runs the boxes Halon reads and changes code in. The deployment names a main provider
# (SANDBOX_PROVIDER) and may name a backup (SANDBOX_BACKUP_PROVIDER), used when the main one cannot start a box. A
# workspace can be held to one provider (Workspace#sandbox_provider), such as one whose data stays in one region, and
# then never fails over, since the point of holding it there is that its code goes nowhere else.
module SandboxProviders
  DOCKER = "docker".freeze
  NORTHFLANK = "northflank".freeze
  BOAT = "boat".freeze
  KEYS = [ DOCKER, NORTHFLANK, BOAT ].freeze
  NAMES = { DOCKER => "Docker", NORTHFLANK => "Northflank", BOAT => "boat.dev" }.freeze
  # Providers whose boxes run Docker, so a repository's setup can start the services its CI names from their own images.
  RUN_IMAGES = [ BOAT ].freeze

  def self.main = ENV["SANDBOX_PROVIDER"].presence

  def self.backup = ENV["SANDBOX_BACKUP_PROVIDER"].presence

  # The providers to try for the workspace's boxes, first to last.
  def self.order_for(workspace)
    return [ workspace.sandbox_provider ] if workspace&.sandbox_provider.present?

    [ main, backup ].compact.uniq
  end

  # Every provider a box may be running on now, so a sweep asks each one.
  def self.in_use
    KEYS & [ main, backup, *Workspace.where.not(sandbox_provider: nil).distinct.pluck(:sandbox_provider), *CodeBox.distinct.pluck(:provider),
             *PreparedCopy.where.not(kept_in: PreparedCopy::KEPT_IN_ARCHIVE).distinct.pluck(:kept_in) ]
  end

  def self.name_of(key) = NAMES.fetch(key, key.to_s)

  def self.runs_images?(workspace) = RUN_IMAGES.include?(order_for(workspace).first)
end
