module Ability
  # The mutable in-flight gate for a call that matched an approval policy.
  # Bound to the exact request via a digest — "approved" provably means this
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

    scope :pending, -> { where(status: STATUS_PENDING) }

    after_create_commit :notify_approvers, if: :pending?

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

    def consume!
      raise NotAllowed, "approval already used" if consumed_at.present?

      update!(consumed_at: Time.current)
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

    def role_sufficient?(membership)
      case required_role
      when WorkspaceMembership.roles[:owner] then membership.owner_role?
      when WorkspaceMembership.roles[:admin] then membership.admin_access?
      else true
      end
    end

    private

    def notify_approvers
      AbilityApprovalNotificationJob.perform_later(approval_id: id)
    end

    # Approver re-validated at click time: still pending and holds the
    # required role now. Self-approval is allowed by default — the human
    # confirming their own agent's exact proposal IS the safety mechanism;
    # policies opt into four-eyes with require.self_approval: false.
    def resolve!(new_status, membership)
      raise NotAllowed, "approval is no longer pending" unless pending?
      raise NotAllowed, "requires the #{required_role} role" unless role_sufficient?(membership)
      if requester?(membership) && !self_approvable?
        raise NotAllowed, "this policy requires approval by someone other than the requester"
      end

      update!(status: new_status, approver: membership, resolved_at: Time.current)
    end
  end
end
