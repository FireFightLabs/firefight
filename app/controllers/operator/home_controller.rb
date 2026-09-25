module Operator
  # The console's front door. Jobs is its first screen, the others arrive with their own pages.
  class HomeController < BaseController
    def show
      redirect_to operator_jobs_path
    end
  end
end
