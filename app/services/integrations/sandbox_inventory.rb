module Integrations
  # What each sandbox provider holds for Firefight, read through the provider contract on every sweep into
  # ProviderSandbox, and the stop, delete and adopt an operator asks for, which go to the provider and close or open the
  # app's rows.
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

    # Records a box the app lost its row for under the workspace and run it was started for, so it is billed from since
    # and stopped like any other. Its provider hands it back with a key the app knows first, and the run's own lock keeps
    # the run from starting a box of its own meanwhile.
    def self.adopt!(provider, ref, workspace:, key:, since:, size:)
      sandboxes = Sandboxes.provider(provider)
      reached = sandboxes.reclaim(ref)
      CodeReading.locked(key) do
        raise Error, "The run this box was started for has another box now, so this one can only be stopped or deleted." if CodeBox.live.exists?(key: key)

        CodeBox.create!(workspace: workspace, key: key, provider: provider, box_ref: ref, **CodeBox.address_columns(reached.address), secret: reached.key,
                        last_used_at: Time.current, box_started_at: since || Time.current, size: size, hourly_micros: sandboxes.hourly_micros_for(size))
      end
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
