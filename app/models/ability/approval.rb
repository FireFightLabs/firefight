module Ability
  # The mutable in-flight gate for a call that matched an approval policy.
  # Bound to the exact request via a digest, "approved" provably means this
  # call with these params in this scope, never the action in general. An
  # approval is consumed by exactly one execution.
  class Approval < ApplicationRecord
    STATUS_PENDING = "pending"
    STATUS_APPROVED = "approved"
    STATUS_DENIED = "denied"
    STATUS_EXPIRED = "expired"
    STATUSES = [ STATUS_PENDING, STATUS_APPROVED, STATUS_DENIED, STATUS_EXPIRED ].freeze

    class NotAllowed < StandardError; end

    belongs_to :workspace
    belongs_to :principal, polymorphic: true, optional: true
    belongs_to :approver, class_name: "WorkspaceMembership", optional: true

    validates :principal_label, :action_key, :request_digest, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :required_role, inclusion: { in: WorkspaceMembership.roles.keys }
    validates :source, inclusion: { in: AbilityGateway::SOURCES }, allow_nil: true
    validates :notify, inclusion: { in: PolicyRule::ApprovalOutcome::NOTIFY_OPTIONS }, allow_nil: true

    scope :pending, -> { where(status: STATUS_PENDING) }

    def self.digest(action_key, params, scope)
      Digest::SHA256.hexdigest(JSON.generate([ action_key, canonical(params), canonical(scope) ]))
    end

    # Deterministic serialization: same request → same digest regardless of
    # key ordering or symbol/string keys.
    def self.canonical(value)
      case value
      when Hash then value.map { |k, v| [ k.to_s, canonical(v) ] }.sort_by(&:first)
      when Array then value.map { |v| canonical(v) }
      else value.as_json
      end
    end

    def approve!(by:)
      resolve!(STATUS_APPROVED, by)
    end

    def deny!(by:)
      resolve!(STATUS_DENIED, by)
    end

    def expire!
      update!(status: STATUS_EXPIRED, resolved_at: Time.current) if pending?
    end

    # One statement, so two callers racing for the same approval cannot both
    # win. Checking consumed_at and then writing it leaves a window where both
    # read nil, and an approval admits exactly one execution.
    def claim
      now = Time.current
      claimed = self.class.where(id: id, status: STATUS_APPROVED, consumed_at: nil).update_all(consumed_at: now, updated_at: now)
      return false if claimed.zero?

      self.consumed_at = now
      true
    end

    def consume!
      raise NotAllowed, "approval already used" unless claim

      self
    end

    def pending? = status == STATUS_PENDING
    def approved? = status == STATUS_APPROVED
    def denied? = status == STATUS_DENIED
    def usable? = approved? && consumed_at.nil?

    def matches_request?(action_key, params, scope)
      request_digest == self.class.digest(action_key, params, scope)
    end

    def requester?(membership)
      principal_type == "WorkspaceMembership" && principal_id == membership.id
    end

    # Named approvers replace the role. The rule picked people, so the role
    # is only how the request is described. Without names, the role decides.
    def named_approvers?
      approver_ids.present?
    end

    def approver?(membership)
      return approver_ids.include?(membership.id) if named_approvers?

      role_sufficient?(membership)
    end

    def role_sufficient?(membership)
      case required_role
      when WorkspaceMembership.roles[:owner] then membership.owner_role?
      when WorkspaceMembership.roles[:admin] then membership.admin_access?
      else true
      end
    end

    # Everyone who should be asked, the named people or every member who
    # holds the required role.
    def approvers
      return workspace.workspace_memberships.where(id: approver_ids) if named_approvers?

      case required_role
      when WorkspaceMembership.roles[:owner] then workspace.workspace_memberships.where(role: WorkspaceMembership.roles[:owner])
      else workspace.workspace_memberships.where(role: [ WorkspaceMembership.roles[:admin], WorkspaceMembership.roles[:owner] ])
      end
    end

    def notify_channel?
      [ nil, PolicyRule::ApprovalOutcome::NOTIFY_CHANNEL, PolicyRule::ApprovalOutcome::NOTIFY_BOTH ].include?(notify)
    end

    def notify_dm?
      [ PolicyRule::ApprovalOutcome::NOTIFY_DM, PolicyRule::ApprovalOutcome::NOTIFY_BOTH ].include?(notify)
    end

    def add_notification!(channel_id:, message_id:)
      update!(notifications: notifications + [ { "channel_id" => channel_id, "message_id" => message_id } ])
    end

    private

    def approver_requirement_message
      return "requires the #{required_role} role" unless named_approvers?

      "only #{approvers.map(&:display_name).to_sentence} can decide this request"
    end

    # A parked chat request carries the payload that produced it, because a
    # person cannot retry a click the way the API and MCP callers retry a
    # call. Replay is enqueued here, after the decision commits, rather than
    # from a model callback, so creating or editing a row elsewhere never
    # triggers platform traffic on its own.
    def resume_parked_request
      return if resume_payload.blank?

      ActiveRecord.after_all_transactions_commit do
        AbilityApprovalResumptionJob.perform_later(approval_id: id)
      end
    end

    # Approver re-validated at click time, still pending and holds the
    # required role now. Self-approval is allowed by default, the human
    # confirming their own agent's exact proposal IS the safety mechanism.
    # Policies opt into four-eyes with require.self_approval: false.
    def resolve!(new_status, membership)
      raise NotAllowed, "approval is no longer pending" unless pending?
      raise NotAllowed, approver_requirement_message unless approver?(membership)
      if requester?(membership) && !self_approvable?
        raise NotAllowed, "this policy requires approval by someone other than the requester"
      end

      update!(status: new_status, approver: membership, resolved_at: Time.current)
      resume_parked_request
    end
  end
end
