module Integrations
  # What each sandbox provider holds for Firefight, read through the provider contract on every sweep into
  # ProviderSandbox, and the stop and delete an operator asks for, which go to the provider and close the app's rows.
  class SandboxInventory
    # One provider that cannot be read keeps its last reading and says why, and the others are still read.
    def self.record!
      SandboxProviders.in_use.each do |key|
        ProviderSandbox.record!(key, Sandboxes.provider(key).inventory)
        SandboxProviderRead.read!(key)
      rescue Sandboxes::Error => error
        SandboxProviderRead.read!(key, error: error.message)
      end
    end

    # A box a run still holds has its row closed first, so the run starts another rather than reading a stopped one.
    def self.stop!(provider, ref)
      CodeBox.live.find_by(provider: provider, box_ref: ref)&.stop!
      Sandboxes.provider(provider).stop(ref)
    end

    # A kept copy's row goes with it, so no later box tries to start from it. An archive in the app's own storage is
    # only its row and attachment.
    def self.delete!(provider, kind, ref)
      if provider == PreparedCopy::KEPT_IN_ARCHIVE
        return PreparedCopy.archives.where(id: ref).destroy_all
      elsif kind == ProviderSandbox::KIND_SNAPSHOT
        Sandboxes.provider(provider).discard(ref)
        PreparedCopy.where(kept_in: provider, kept_ref: ref).destroy_all
      else
        CodeBox.live.find_by(provider: provider, box_ref: ref)&.stop!
        Sandboxes.provider(provider).delete(ref)
      end
      ProviderSandbox.gone!(provider, kind, ref)
    end
  end
end
