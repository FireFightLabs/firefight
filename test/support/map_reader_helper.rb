# Someone who reads the whole map of the first workspace, for tests about routing rather than about who may read.
module MapReaderHelper
  def map_reader = workspace_memberships(:alice_workspace_one)
end
