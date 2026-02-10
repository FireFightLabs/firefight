module Interactions
  class ViewClosedHandler
    def self.execute(_interaction)
      Rails.logger.info("Modal closed without submission")
      nil
    end
  end
end
