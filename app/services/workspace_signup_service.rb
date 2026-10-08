# Creates a workspace from the signup page. Someone new is made here, from what their provider verified, so a person
# exists only once they have a workspace, and a name the workspace refuses leaves nobody behind. sign_up_method is the
# UserIdentity provider the person signed in with, told to the people running Firefight.
class WorkspaceSignupService
  def create(name:, user: nil, claims: nil, invite_code: nil, sign_up_method: nil)
    ActiveRecord::Base.transaction do
      user ||= AuthenticationService.new.sign_in_with(claims, create_user: true).user
      membership = Workspace.sign_up!(name: name, user: user, invite_code: invite_code)
      SignupNotificationService.announce(SignupNotificationService::WORKSPACE_CREATED, membership.workspace, membership,
                                         sign_up_method: sign_up_method)
      membership
    end
  end
end
