module ApplicationCable
  # The portal authenticates with the same HttpOnly session cookie the JSON API
  # uses, so the socket reads the signed-in user from Warden rather than
  # inventing a second credential for websockets.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = verified_user
      logger.add_tags("ActionCable", current_user.id)
    end

    private

    def verified_user
      user = env["warden"]&.user
      reject_unauthorized_connection unless user&.active?

      user
    end
  end
end
