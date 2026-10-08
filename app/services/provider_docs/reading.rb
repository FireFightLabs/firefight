module ProviderDocs
  # What reading one source found. pages holds each page read, with content nil for one that did not change since its
  # revision. listed is every page the source still names, so a page it dropped is removed. failed names each page that
  # could not be read this time, which keeps the copy it had.
  Reading = Data.define(:pages, :listed, :failed, :version, :license) do
    def initialize(failed: {}, version: nil, license: nil, **) = super
  end
end
