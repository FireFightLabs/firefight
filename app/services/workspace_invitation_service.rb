# Invitations by email. The rules live on WorkspaceInvitation, this sends the emails and signs the person in.
class WorkspaceInvitationService
  # More than this in one request is a list pasted by mistake.
  MAX_PER_REQUEST = 20

  Outcome = Data.define(:invitations, :error)

  def initialize(workspace)
    @workspace = workspace
  end

  # Takes addresses separated by commas, spaces or new lines. Inviting someone with an invitation already open sends
  # it again. link_url turns a raw token into the address the email points at.
  def invite(text, by:, link_url:)
    emails = text.to_s.split(/[\s,;]+/).map { |email| email.strip.downcase }.compact_blank.uniq
    error = invite_error(emails)
    return Outcome.new(invitations: [], error: error) if error

    invitations = WorkspaceInvitation.transaction do
      emails.map { |email| open_invitation(email, by) }
    end
    invitations.each { |invitation| deliver(invitation, link_url) }
    Outcome.new(invitations: invitations, error: nil)
  rescue ActiveRecord::RecordInvalid => e
    Outcome.new(invitations: [], error: e.record.errors.full_messages.to_sentence)
  end

  def resend(invitation, link_url:)
    reason = invitation.resend_blocked_reason
    raise OptionGuards::Blocked, reason if reason

    deliver(invitation, link_url)
  end

  # Nil when the link is unknown, expired, already used, or its invitation was taken back.
  def self.accept(token)
    login_token = LoginToken.consume(token, purpose: LoginToken::INVITE)
    invitation = login_token&.workspace_invitation
    return nil unless invitation&.pending?

    claims = AuthenticationService::Claims.new(
      provider: UserIdentity::EMAIL, uid: invitation.email, email: invitation.email, email_verified: true
    )
    result = AuthenticationService.new.sign_in_with(claims, create_user: true)
    invitation.accept!(result.user)
  end

  private

  def invite_error(emails)
    return "Enter at least one email address." if emails.empty?
    return "Invite at most #{MAX_PER_REQUEST} people at a time." if emails.size > MAX_PER_REQUEST

    invalid = emails.reject { |email| WorkspaceInvitation.valid_email?(email) }
    return "#{invalid.to_sentence} #{invalid.one? ? "is not a valid email address" : "are not valid email addresses"}." if invalid.any?

    WorkspaceInvitation.unavailable_reason || WorkspaceInvitation.send_blocked_reason(@workspace, emails.size)
  end

  def open_invitation(email, by)
    @workspace.invitations.pending.find_by(email: email) ||
      WorkspaceInvitation.transaction(requires_new: true) do
        @workspace.invitations.create!(email: email, invited_by: by, last_sent_at: Time.current)
      end
  rescue ActiveRecord::RecordNotUnique
    # Another admin invited the same address a moment earlier.
    @workspace.invitations.pending.find_by!(email: email)
  end

  def deliver(invitation, link_url)
    token = invitation.issue_link!
    WorkspaceInvitationMailer.invite(invitation, url: link_url.call(token)).deliver_later
  end
end
