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

    # A request a token or a machine made is approved by a person in a session of their own, so no token approves what a
    # token asked for.
    APPROVE_WITH_TOKEN = "A request made with a token is approved only by a person signed in to Firefight or answering in chat, never with a token.".freeze
    MACHINE_REQUESTERS = [ Agent.name, ApiKey.name, SystemAgent.name ].freeze

    # What deciding a request is authorized as, and the scope key that names the request decided.
    DECIDE_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_APPROVALS, Ability::Action::ACTION_UPDATE)
    SCOPE_APPROVAL = "approval"

    belongs_to :workspace
    belongs_to :principal, polymorphic: true, optional: true
    belongs_to :approver, polymorphic: true, optional: true
    # The unattended rule that approved the call ahead, in place of an approver.
    belongs_to :approved_under_rule, class_name: "Ability::UnattendedRule", optional: true
    belongs_to :incident, optional: true
    # The workflow run whose step asked for it.
    belongs_to :workflow_run, class_name: "Workflow::Run", optional: true

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

    # with_token is a decision sent with a token, over the API or MCP, rather than by a person in a session.
    def approve!(by:, with_token: false)
      resolve!(STATUS_APPROVED, by, with_token: with_token)
    end

    def deny!(by:)
      resolve!(STATUS_DENIED, by)
    end

    # A call a person runs once it is approved, rather than one replayed the moment it is. Its approval lasts RUN_WINDOW.
    def hold_for_run!
      update!(held_for_run: true)
    end

    # An approved call nobody ran in time expires, in one statement, so a run claiming it at the same moment stands. It
    # keeps why, which the caller has every message it was asked in say (ApprovalNotificationService.mark_resolved!).
    def lapse_run!
      now = Time.current
      lapsed = self.class.where(id: id, status: STATUS_APPROVED, consumed_at: nil).where(run_expires_at: ..now)
                         .update_all(status: STATUS_EXPIRED, withdrawn_reason: lapsed_reason, updated_at: now)
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

    # Only from pending, in one statement, so an approval given at the same moment stands. reason is why it was withdrawn,
    # as a sentence, which the caller has every message it was asked in say in place of its buttons.
    def expire!(reason:)
      now = Time.current
      self.class.where(id: id, status: STATUS_PENDING).update_all(status: STATUS_EXPIRED, withdrawn_reason: reason, resolved_at: now, updated_at: now)
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

    # A workflow's Approval step asking people to decide, rather than a call waiting to run.
    def workflow_question? = action_key == Ability::Action::WORKFLOW_APPROVAL

    # What a workflow's Approval step asks, and what it said approvers should know.
    def question = (self[:params]["question"] if workflow_question?)
    def question_details = (self[:params]["details"] if workflow_question?)

    # The scope a decision on this request is authorized with, which names it, so the gateway can let a person the
    # request names decide it (decides_by_name?).
    def decision_scope = self.class.decision_scope_for(id)

    def self.decision_scope_for(id) = { SCOPE_APPROVAL => id.to_s }

    # Someone a workflow's Approval step named may decide that one request without approvals.update, and nothing else.
    # Anyone it reaches through a role, and every other request, still needs the grant. loaded is the request when the
    # caller holds it already, used only when it is the one the scope names.
    def self.decides_by_name?(principal, action_key, scope, workspace, loaded: nil)
      return false unless action_key == DECIDE_KEY && principal.is_a?(WorkspaceMembership)

      id = scope.to_h.stringify_keys[SCOPE_APPROVAL]
      approval = id.present? && ((loaded if loaded&.id.to_s == id.to_s && loaded.workspace_id == workspace.id) || workspace.ability_approvals.find_by(id: id))
      approval.present? && approval.named_decider?(principal)
    end

    def named_decider?(principal)
      workflow_question? && named_approvers? && principal.is_a?(WorkspaceMembership) &&
        approver_ids.map { |ref| Ability::Principal.reference(ref) }.include?(Ability::Principal.reference_for(principal))
    end

    # Why this principal may not decide this request at all, through the gateway, or nil when they may. The rules of the
    # request itself are decide_blocked_reason's.
    def decide_denied_reason(principal)
      action = Ability::Action.lookup(DECIDE_KEY, workspace)
      return if principal && AbilityGateway.permitted?(principal, action, DECIDE_KEY, workspace, decision_scope, approval: self)

      "You don't have permission to decide this request. Ask a workspace admin to grant you approvals access under Gateway, Permissions."
    end

    # Where it is asked in a channel. A workflow's Approval step asks where its run asks people (Workflow::Run#asking_channel_id),
    # its incident's channel first. Every other request asks in the incidents channel.
    def request_channel_id
      return workflow_run.asking_channel_id(incident) if workflow_question? && workflow_run

      workspace.incidents_channel_id.presence
    end

    # The call this approval let through, as the gateway ledgered it, the latest when it was tried more than once. nil
    # until it is approved and runs.
    def run
      return unless approved?

      Ability::Invocation.where(approval_id: id, decision: Ability::Invocation::DECISION_ALLOW).order(:created_at).last
    end

    def pending? = status == STATUS_PENDING
    def approved? = status == STATUS_APPROVED
    def denied? = status == STATUS_DENIED
    def expired? = status == STATUS_EXPIRED
    def dismissed? = status == STATUS_DISMISSED
    def run_lapsed? = run_expires_at.present? && run_expires_at <= Time.current
    def usable? = approved? && consumed_at.nil? && !run_lapsed?

    # Why this principal cannot decide it now, or nil when they can, by the same rules deciding enforces.
    def decide_blocked_reason(principal)
      return "This request was already decided." unless pending?
      return "#{approver_requirement_message.upcase_first}." unless approver?(principal)
      return "This policy requires approval by someone other than the requester." if requester?(principal) && !self_approvable?

      nil
    end

    # A request a token or a machine made, which a token could otherwise approve for itself or for another token.
    def made_with_token?
      AbilityGateway::TOKEN_SOURCES.include?(source) || MACHINE_REQUESTERS.include?(principal_type)
    end

    # Why approving this request with a token is refused, or nil.
    def approve_with_token_blocked_reason = (APPROVE_WITH_TOKEN if made_with_token?)

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

    # Gives back a claim whose message never reached the member, so they can be asked again.
    def release_ask!(member)
      self.class.where(id: id).update_all([ "asked_member_ids = asked_member_ids - ?::text, updated_at = ?", member.id.to_s, Time.current ])
      reload
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

    # A change Halon asked for in a chat is always asked in the chat's thread (Conversation::HeldCalls). Where else is
    # the rule's to say. A rule naming the channel, direct messages or both is followed as it is for anyone. A rule on
    # Default asks a chat's request of its approvers directly rather than in the shared incidents channel, and the
    # channel only when nobody could be asked directly (ApprovalNotificationService.post!). Any other request on Default
    # is asked in the channel, as it was before Default existed, and so is one whose rule stored nothing.
    def from_chat? = source == AbilityGateway::SOURCE_CONVERSATION

    # A chat's request whose rule is on Default.
    def chat_default? = from_chat? && notify == PolicyRule::ApprovalOutcome::NOTIFY_DEFAULT

    def notify_channel?
      !chat_default? && [ nil, PolicyRule::ApprovalOutcome::NOTIFY_DEFAULT, PolicyRule::ApprovalOutcome::NOTIFY_CHANNEL,
                          PolicyRule::ApprovalOutcome::NOTIFY_BOTH ].include?(notify)
    end

    def notify_dm?
      chat_default? || [ PolicyRule::ApprovalOutcome::NOTIFY_DM, PolicyRule::ApprovalOutcome::NOTIFY_BOTH ].include?(notify)
    end

    def add_notification!(channel_id:, message_id:)
      update!(notifications: notifications + [ { "channel_id" => channel_id, "message_id" => message_id } ])
    end

    # What followed a command typed in the chat platform, in the platform's own markup. People read it as the platform
    # shows it, and the record keeps it as sent, since the digest and a resumed command are bound to it.
    def platform_text
      asked = self[:params]
      asked["text"].presence if source == AbilityGateway::SOURCE_SLACK && asked.key?("command")
    end

    # The params as people read them, given each platform text mapped to how it reads.
    def params_shown(read)
      text = platform_text
      text ? self[:params].merge("text" => read.fetch(text, text)) : self[:params]
    end

    private

    def lapsed_reason = "Nobody ran it within #{ActiveSupport::Duration.build(RUN_WINDOW.to_i).inspect} of its approval."

    def approver_requirement_message
      return "requires the #{required_role} role" unless named_approvers?

      "only #{approvers.map(&:actor_display_name).to_sentence} can decide this request"
    end

    def membership_or_nil(principal)
      principal if principal.is_a?(WorkspaceMembership)
    end

    # A person cannot retry a click the way API callers retry a call, so the parked payload is
    # replayed. Enqueued after commit so editing a row elsewhere never triggers platform traffic.
    # Why approving would do something nobody asked for, such as publishing a workflow changed since it was asked about.
    def approve_blocked_reason
      Workflow.publish_approval_blocked_reason(self) if resume_payload.to_h["kind"] == Workflow::PUBLISH_APPROVAL_KIND
    end

    # A call held for a run is scheduled to lapse by whoever holds it. Any other is scheduled here, after commit.
    def expire_unheld_approval
      ActiveRecord.after_all_transactions_commit { ApprovedCallExpiryJob.set(wait_until: run_expires_at).perform_later(id) }
    end

    def resume_parked_request
      return if resume_payload.blank?

      ActiveRecord.after_all_transactions_commit do
        AbilityApprovalResumptionJob.perform_later(approval_id: id)
      end
    end

    # Self-approval is allowed by default, the human confirming their own agent's proposal
    # is the safety mechanism. Policies opt into four-eyes with require.self_approval: false.
    def resolve!(new_status, principal, with_token: false)
      raise NotAllowed, "approval is no longer pending" unless pending?
      raise NotAllowed, approver_requirement_message unless approver?(principal)
      blocked = (with_token && approve_with_token_blocked_reason) || approve_blocked_reason if new_status == STATUS_APPROVED
      raise NotAllowed, blocked if blocked
      if requester?(principal) && !self_approvable?
        raise NotAllowed, "this policy requires approval by someone other than the requester"
      end

      now = Time.current
      # Every approved call lapses unused after RUN_WINDOW, a caller that never comes back with it included. A workflow's
      # question admits no call, so it has nothing to lapse.
      run_by = (now + RUN_WINDOW if new_status == STATUS_APPROVED && !workflow_question?)
      # One guarded statement, so an approve and a deny landing together cannot both win.
      decided = self.class.where(id: id, status: STATUS_PENDING).update_all(
        status: new_status, approver_type: principal.class.polymorphic_name, approver_id: principal.id,
        resolved_at: now, run_expires_at: run_by, updated_at: now
      )
      raise NotAllowed, "approval is no longer pending" if decided.zero?

      reload
      expire_unheld_approval if run_by && !held_for_run? && resume_payload.blank?
      resume_parked_request
    end
  end
end
