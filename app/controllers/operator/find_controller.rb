module Operator
  # Finds a record from a pasted id or incident number. Opens it when there is exactly one match, otherwise lists the
  # matches.
  class FindController < BaseController
    def show
      query = params[:q].to_s
      matches = Finder.new(query).matches
      return redirect_to(FindMatchSerializer.path_for(matches.sole)) if matches.one?

      render inertia: "operator/find", props: { query: query, matches: FindMatchSerializer.many(matches) }
    end
  end
end
