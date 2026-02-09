# Handles modal close events (user clicks "Cancel" or X)
module Interactions
  class ViewClosedHandler
    def self.execute(_payload)
      Rails.logger.info("Modal closed without submission")
      nil
    end
  end
end
