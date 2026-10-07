# Creates a workspace from the signup page. Someone new is made here, from what their provider verified, so a person
# exists only once they have a workspace, and a name the workspace refuses leaves nobody behind.
class WorkspaceSignupService
  def create(name:, user: nil, claims: nil, invite_code: nil)
    ActiveRecord::Base.transaction do
      user ||= AuthenticationService.new.sign_in_with(claims, create_user: true).user
      Workspace.sign_up!(name: name, user: user, invite_code: invite_code)
    end
  end
end
