# When the sweep last read a sandbox provider's holdings, and why the read failed when it did, so a provider that cannot
# be asked is said rather than looking empty.
class SandboxProviderRead < ApplicationRecord
  def self.read!(provider, error: nil)
    upsert({ provider: provider, read_at: Time.current, error: error }, unique_by: :provider)
  end
end
