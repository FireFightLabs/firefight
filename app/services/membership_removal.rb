# An admin removing a member. The row stays for the history that names them, and everything that let them in stops at
# once. Their personal tokens and connected agents are revoked, and their open pages in this workspace are cut off, so a
# socket from before the removal cannot keep streaming. The gateway refuses whatever they left running
# (AbilityGateway.permitted?).
class MembershipRemoval
  class Blocked < StandardError; end

  def self.remove!(membership, by:)
    reason = membership.removal_blocked_reason(by)
    raise Blocked, reason if reason
    return false unless membership.mark_removed!

    revoke_access!(membership)
    ActionCable.server.remote_connections.where(current_user: membership.user, current_workspace_id: membership.workspace_id).disconnect
    true
  end

  # Their tokens stay revoked, so they make new ones once they are back.
  def self.restore!(membership)
    reason = membership.restore_blocked_reason
    raise Blocked, reason if reason

    membership.restore!
  end

  def self.revoke_access!(membership)
    now = Time.current
    membership.personal_api_keys.where(deleted_at: nil).find_each(&:soft_delete!)
    membership.oauth_access_tokens.where(revoked_at: nil).update_all(revoked_at: now)
    membership.oauth_access_grants.where(revoked_at: nil).update_all(revoked_at: now)
  end
  private_class_method :revoke_access!
end
