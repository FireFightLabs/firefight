module Integrations
  module Providers
    Aws = Provider.new(
      key: "aws",
      pack: "Integrations::Packs::Aws",
      adapter: "Integrations::Capabilities::Aws"
    )
  end
end
