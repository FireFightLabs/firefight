module Operator
  # The console's front door, which opens on incidents until the overview arrives.
  class HomeController < BaseController
    def show
      redirect_to operator_incidents_path
    end
  end
end
