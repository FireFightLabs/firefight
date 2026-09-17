module ApplicationCable
  # A socket belongs to whoever the session cookie says opened the page.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = signed_in_user || reject_unauthorized_connection
    end

    private

    def signed_in_user
      user_id = request.session[:user_id]
      user_id && User.find_by(id: user_id)
    end
  end
end
