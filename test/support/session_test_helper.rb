module SessionTestHelper
  # Every request loads the signed in workspace afresh, as a real session does. Handing each request the test's own
  # record kept whatever an earlier request had loaded on it, so a deleted row was still drawn after its redirect.
  module SignedInWorkspace
    private

    def signed_in_workspace_id = nil

    def resolve_current_workspace
      signed_in_workspace_id ? Workspace.find_by(id: signed_in_workspace_id) : super
    end
  end
  ApplicationController.prepend(SignedInWorkspace)

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:signed_in_workspace_id).returns(workspace.id)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
