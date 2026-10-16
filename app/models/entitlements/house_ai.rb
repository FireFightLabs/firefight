module Entitlements
  # How a hosted build describes the AI it runs Halon on when a workspace brings no key of its own, as setup's AI step
  # offers it. title heads the choice and detail is the finished sentences under it, since only the backend knows who
  # pays and what the workspace was given.
  HouseAi = Data.define(:title, :detail)
end
