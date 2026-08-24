module Ability
  # The atomic permissioned unit of the Ability Gateway. System actions are
  # global rows (workspace_id nil) derived from ApiKey resource/action
  # constants. Tool actions are workspace-scoped and minted by integrations.
  class Action < ApplicationRecord
    KIND_SYSTEM = "system"
    KIND_TOOL = "tool"
    KINDS = [ KIND_SYSTEM, KIND_TOOL ].freeze

    RISK_READ = "read"
    RISK_WRITE = "write"
    RISK_DESTRUCTIVE = "destructive"
    RISK_LEVELS = [ RISK_READ, RISK_WRITE, RISK_DESTRUCTIVE ].freeze

    RISK_BY_CRUD_ACTION = {
      ApiKey::ACTION_READ => RISK_READ,
      ApiKey::ACTION_CREATE => RISK_WRITE,
      ApiKey::ACTION_UPDATE => RISK_WRITE,
      ApiKey::ACTION_DELETE => RISK_DESTRUCTIVE
    }.freeze

    KEY_FORMAT = /\A[a-z0-9_]+(\.[a-z0-9_]+)+\z/

    belongs_to :workspace, optional: true
    belongs_to :source, polymorphic: true, optional: true
    has_many :grants, class_name: "Ability::Grant", foreign_key: :action_id, dependent: :destroy,
             inverse_of: :action
    has_many :role_actions, class_name: "Ability::RoleAction", foreign_key: :action_id,
             dependent: :destroy, inverse_of: :action

    validates :kind, inclusion: { in: KINDS }
    validates :risk_level, inclusion: { in: RISK_LEVELS }
    validates :key, presence: true, format: { with: KEY_FORMAT }
    validates :key, uniqueness: { scope: :workspace_id }
    validate :system_actions_are_global

    scope :system_actions, -> { where(kind: KIND_SYSTEM) }

    def self.system_key(resource, action)
      "#{resource}.#{action}"
    end

    # A key resolves to the global system action or the workspace's own
    # tool action. Keys inside the system space self-heal (same rule as
    # system!, so an unseeded environment can't deny valid actions). Any
    # other unknown key resolves to nil and the gateway denies it.
    def self.lookup(key, workspace)
      found = where(workspace_id: [ nil, workspace&.id ]).find_by(key: key)
      return found if found

      system!(key) if ApiKey.managed_ability_keys.include?(key)
    end

    # Lazily materializes a system action so grant writes never race the
    # seed. Safe under parallel creation via the partial unique index.
    def self.system!(key)
      crud_action = key.split(".").last
      find_or_create_by!(workspace_id: nil, key: key) do |action|
        action.kind = KIND_SYSTEM
        action.risk_level = RISK_BY_CRUD_ACTION.fetch(crud_action, RISK_WRITE)
        action.reversible = action.risk_level != RISK_DESTRUCTIVE
      end
    rescue ActiveRecord::RecordNotUnique
      find_by!(workspace_id: nil, key: key)
    end

    def self.sync_system_actions!
      ApiKey::RESOURCES.each do |resource|
        ApiKey::ACTIONS.each do |action|
          system!(system_key(resource, action))
        end
      end
    end

    def system?
      kind == KIND_SYSTEM
    end

    # Config ≠ permission: a tool action also needs whatever minted it to be
    # wired for the requested scope. What "wired" means belongs to the source,
    # not to the gateway. System actions have no configuration dimension.
    def configured_for?(scope)
      return true if system?

      source.present? && source.configured_for?(scope)
    end

    private

    def system_actions_are_global
      errors.add(:workspace_id, "must be blank for system actions") if system? && workspace_id.present?
      errors.add(:workspace_id, "is required for tool actions") if !system? && workspace_id.blank?
    end
  end
end
