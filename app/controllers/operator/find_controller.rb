module Operator
  # Whatever an operator pasted into Find. One match opens it, anything else lists what matched.
  class FindController < BaseController
    def show
      query = params[:q].to_s
      matches = Finder.new(query).matches
      return redirect_to(OperatorFindMatchSerializer.path_for(matches.sole)) if matches.one?

      render inertia: "operator/find", props: { query: query, matches: OperatorFindMatchSerializer.many(matches) }
    end
  end
end
