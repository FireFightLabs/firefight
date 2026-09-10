module Ability
  # Bound to the exact request by a digest, so "approved" means this call
  # with these params, never the action in general. Consumed by exactly one execution.
  class Approval < ApplicationRecord
    STATUS_PENDING = "pending"
    STATUS_APPROVED = "approved"
    STATUS_DENIED = "denied"
    STATUS_EXPIRED = "expired"
    STATUSES = [ STATUS_PENDING, STATUS_APPROVED, STATUS_DENIED, STATUS_EXPIRED ].freeze

    class NotAllowed < StandardError; end

    belongs_to :workspace
    belongs_to :principal, polymorphic: true, optional: true
    belongs_to :approver, polymorphic: true, optional: true

    validates :principal_label, :action_key, :request_digest, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :required_role, inclusion: { in: WorkspaceMembership.roles.keys }
    validates :source, inclusion: { in: AbilityGateway::SOURCES }, allow_nil: true
    validates :notify, inclusion: { in: PolicyRule::ApprovalOutcome::NOTIFY_OPTIONS }, allow_nil: true

    scope :pending, -> { where(status: STATUS_PENDING) }

    def self.digest(action_key, params, scope)
      Digest::SHA256.hexdigest(JSON.generate([ action_key, canonical(params), canonical(scope) ]))
    end

    # Same digest regardless of key order or symbol versus string keys.
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

    # One statement, so two callers racing for the same approval cannot both win.
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

    def requester?(candidate)
      principal_type == candidate.class.polymorphic_name && principal_id == candidate.id
    end

    # Named approvers replace the role. A machine decides only when it was
    # named and the rule said agents may.
    def named_approvers?
      approver_ids.present?
    end

    def approver?(principal)
      reference = Ability::Principal.reference_for(principal)
      if named_approvers?
        return false unless approver_ids.map { |ref| Ability::Principal.reference(ref) }.include?(reference)

        return principal.is_a?(WorkspaceMembership) || agents_may_approve?
      end

      principal.is_a?(WorkspaceMembership) && role_sufficient?(membership_or_nil(principal))
    end

    def role_sufficient?(membership)
      case required_role
      when WorkspaceMembership.roles[:owner] then membership.owner_role?
      when WorkspaceMembership.roles[:admin] then membership.admin_access?
      else true
      end
    end

    # Machines are asked nothing, they poll.
    def approvers
      return named_approver_records if named_approvers?

      case required_role
      when WorkspaceMembership.roles[:owner] then workspace.workspace_memberships.where(role: WorkspaceMembership.roles[:owner])
      else workspace.workspace_memberships.where(role: [ WorkspaceMembership.roles[:admin], WorkspaceMembership.roles[:owner] ])
      end
    end

    def human_approvers
      approvers.select { |approver| approver.is_a?(WorkspaceMembership) }
    end

    def named_approver_records
      approver_ids.filter_map { |ref| Ability::Principal.find_reference(workspace, Ability::Principal.reference(ref)) }
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

      "only #{approvers.map(&:actor_display_name).to_sentence} can decide this request"
    end

    def membership_or_nil(principal)
      principal if principal.is_a?(WorkspaceMembership)
    end

    # A person cannot retry a click the way API callers retry a call, so the parked payload is
    # replayed. Enqueued after commit so editing a row elsewhere never triggers platform traffic.
    def resume_parked_request
      return if resume_payload.blank?

      ActiveRecord.after_all_transactions_commit do
        AbilityApprovalResumptionJob.perform_later(approval_id: id)
      end
    end

    # Self-approval is allowed by default, the human confirming their own agent's proposal
    # is the safety mechanism. Policies opt into four-eyes with require.self_approval: false.
    def resolve!(new_status, principal)
      raise NotAllowed, "approval is no longer pending" unless pending?
      raise NotAllowed, approver_requirement_message unless approver?(principal)
      if requester?(principal) && !self_approvable?
        raise NotAllowed, "this policy requires approval by someone other than the requester"
      end

      update!(status: new_status, approver: principal, resolved_at: Time.current)
      resume_parked_request
    end
  end
end
