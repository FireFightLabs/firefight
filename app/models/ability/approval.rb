module Ability
  # Bound to the exact request by a digest, so "approved" means this call
  # with these params, never the action in general. Consumed by exactly one execution.
  class Approval < ApplicationRecord
    include Ability::ConnectionNamed

    STATUS_PENDING = "pending"
    STATUS_APPROVED = "approved"
    STATUS_DENIED = "denied"
    STATUS_EXPIRED = "expired"
    # Approved, then the person who asked chose not to run it.
    STATUS_DISMISSED = "dismissed"
    STATUSES = [ STATUS_PENDING, STATUS_APPROVED, STATUS_DENIED, STATUS_EXPIRED, STATUS_DISMISSED ].freeze

    # An approved call a person runs by hand, such as one Halon asked for in a chat, waits this long for them. After it,
    # what was approved may no longer be what is there, so it has to be asked for again.
    RUN_WINDOW = 1.hour

    class NotAllowed < StandardError; end

    belongs_to :workspace
    belongs_to :principal, polymorphic: true, optional: true
    belongs_to :approver, polymorphic: true, optional: true
    # The unattended rule that approved the call ahead, in place of an approver.
    belongs_to :approved_under_rule, class_name: "Ability::UnattendedRule", optional: true
    belongs_to :incident, optional: true

    validates :principal_label, :action_key, :request_digest, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :required_role, inclusion: { in: WorkspaceMembership.roles.keys }
    validates :source, inclusion: { in: AbilityGateway::SOURCES }, allow_nil: true
    validates :notify, inclusion: { in: PolicyRule::ApprovalOutcome::NOTIFY_OPTIONS }, allow_nil: true

    scope :pending, -> { where(status: STATUS_PENDING) }

    # Shared so the gateway and the chat's confirm step read a rule the same way.
    def self.requirement_attributes(requirement)
      {
        required_role: requirement["role"],
        self_approvable: requirement.fetch("self_approval", true),
        approver_ids: Ability::Principal.references(requirement["approvers"]),
        agents_may_approve: requirement.fetch("agents_may_approve", false),
        notify: requirement["notify"],
        on_call_may_approve: requirement.fetch(PolicyRule::ApprovalOutcome::ON_CALL, false)
      }
    end

    # Builds an unsaved approval so asking never writes a row.
    def self.self_approvable_by?(principal, requirement, workspace:)
      draft = new(
        workspace: workspace, principal_type: principal.class.polymorphic_name, principal_id: principal.id,
        **requirement_attributes(requirement)
      )
      draft.self_approvable? && draft.approver?(principal)
    end

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

    # A call a person runs once it is approved, rather than one replayed the moment it is. Its approval lasts RUN_WINDOW.
    def hold_for_run!
      update!(held_for_run: true)
    end

    # An approved call nobody ran in time expires, in one statement, so a run claiming it at the same moment stands.
    def lapse_run!
      now = Time.current
      lapsed = self.class.where(id: id, status: STATUS_APPROVED, consumed_at: nil).where(run_expires_at: ..now)
                         .update_all(status: STATUS_EXPIRED, updated_at: now)
      reload
      lapsed == 1
    end

    # The person who asked chose not to run what was approved. Only while it is unused, in one statement.
    def dismiss!
      now = Time.current
      dismissed = self.class.where(id: id, status: STATUS_APPROVED, consumed_at: nil).update_all(status: STATUS_DISMISSED, updated_at: now)
      reload
      dismissed == 1
    end

    # Only from pending, in one statement, so an approval given at the same moment stands.
    def expire!
      now = Time.current
      self.class.where(id: id, status: STATUS_PENDING).update_all(status: STATUS_EXPIRED, resolved_at: now, updated_at: now)
      reload
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
    def expired? = status == STATUS_EXPIRED
    def dismissed? = status == STATUS_DISMISSED
    def run_lapsed? = run_expires_at.present? && run_expires_at <= Time.current
    def usable? = approved? && consumed_at.nil? && !run_lapsed?

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
      return true if on_call_approver?(principal)

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
      else workspace.workspace_memberships.admins_and_owners
      end
    end

    # Who decided, as a person reads it: the approver, or the unattended rule that decided ahead.
    def decider_name
      return approver.actor_display_name if approver
      return "Unattended rule: #{approved_under_rule.sentence}" if approved_under_rule

      nil
    end

    def human_approvers
      approvers.select { |approver| approver.is_a?(WorkspaceMembership) }
    end

    # Whoever is on call for the incident, when the rule lets them decide and none of its approvers is working the
    # incident or asked for the call. Only then are they asked, so a request someone in the incident can decide never
    # wakes anyone.
    def on_call_to_ask
      return [] unless on_call_may_approve? && incident

      here = [ *incident.participants, principal ].compact
      return [] if human_approvers.any? { |approver| here.include?(approver) }

      incident.on_call_members
    end

    # Claims asking one member directly, in one statement, so a request is never sent to the same person twice.
    def claim_ask!(member)
      asked = [ member.id ].to_json
      won = self.class.where(id: id).where.not("asked_member_ids @> ?::jsonb", asked)
                      .update_all([ "asked_member_ids = asked_member_ids || ?::jsonb, updated_at = ?", asked, Time.current ])
      reload
      won == 1
    end

    def on_call_approver?(principal)
      on_call_may_approve? && incident.present? && principal.is_a?(WorkspaceMembership) && incident.on_call_members.include?(principal)
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

      now = Time.current
      run_by = (now + RUN_WINDOW if held_for_run? && new_status == STATUS_APPROVED)
      update!(status: new_status, approver: principal, resolved_at: now, run_expires_at: run_by)
      resume_parked_request
    end
  end
end
