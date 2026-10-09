# Where this workspace's code boxes run. Empty follows the deployment's main and backup provider. Set, the workspace's
# boxes run only on that provider, never failing over, so its code stays where it was put. Only the people who run
# the deployment set it, since it is a fact about the deployment's providers and not a workspace setting.
module Workspace::SandboxPlacement
  extend ActiveSupport::Concern

  included do
    normalizes :sandbox_provider, with: ->(value) { value.to_s.strip.presence }
    validates :sandbox_provider, inclusion: { in: SandboxProviders::KEYS }, allow_nil: true
  end
end
