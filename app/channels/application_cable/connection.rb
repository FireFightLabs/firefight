module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # The workspace the page was opened in, so leaving one workspace cuts only its pages.
    identified_by :current_user, :current_workspace_id

    def connect
      self.current_user = signed_in_user || reject_unauthorized_connection
      self.current_workspace_id = request.session[:workspace_id]
    end

    private

    def signed_in_user
      user_id = request.session[:user_id]
      user_id && User.find_by(id: user_id)
    end
  end
end
