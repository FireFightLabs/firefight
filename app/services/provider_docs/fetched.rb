module ProviderDocs
  # One page a source read, with where it is kept, the address it came from, its text, or nil when it did not change since
  # revision, and the revision to ask with next time.
  Fetched = Data.define(:path, :url, :content, :revision)
end
