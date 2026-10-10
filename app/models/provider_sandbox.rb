# What a sandbox provider reported it holds for Firefight when the sweep last asked, a box or a kept copy, so what runs
# and costs at a provider can be set against the app's own rows (CodeBox, PreparedCopy). One the provider stopped
# reporting has gone_at.
class ProviderSandbox < ApplicationRecord
  KIND_BOX = "box".freeze
  KIND_SNAPSHOT = "snapshot".freeze
  KINDS = [ KIND_BOX, KIND_SNAPSHOT ].freeze
  # What a kept copy is for. A box is always a run's.
  PURPOSE_RUN = "run".freeze
  PURPOSE_IMAGE = "image".freeze
  PURPOSE_PREPARED = "prepared".freeze
  # Each provider's own state, said in one vocabulary. A kept copy is ready once it can be started from.
  PHASE_STARTING = "starting".freeze
  PHASE_RUNNING = "running".freeze
  PHASE_STOPPING = "stopping".freeze
  PHASE_STOPPED = "stopped".freeze
  PHASE_READY = "ready".freeze
  PHASE_FAILED = "failed".freeze
  PHASES = [ PHASE_STARTING, PHASE_RUNNING, PHASE_STOPPING, PHASE_STOPPED, PHASE_READY, PHASE_FAILED ].freeze

  validates :kind, inclusion: { in: KINDS }

  # Writes what the provider holds now, each by its kind and ref, and marks what it no longer holds as gone.
  def self.record!(provider, held, at: Time.current)
    transaction do
      held.each do |each|
        row = find_or_initialize_by(provider: provider, kind: each.kind, ref: each.ref)
        row.first_seen_at ||= at
        row.update!(name: each.name, purpose: each.purpose, state: each.state, phase: each.phase, size: each.size, started_at: each.started_at, provider_updated_at: each.updated_at,
                    byte_size: each.byte_size, monthly_micros: each.monthly_micros, last_seen_at: at, gone_at: nil)
      end
      where(provider: provider, gone_at: nil).where.not(id: where(provider: provider, last_seen_at: at).select(:id)).update_all(gone_at: at, updated_at: at)
    end
  end

  # Marks one thing gone as soon as it is stopped or deleted, rather than at the next read.
  def self.gone!(provider, kind, ref) = where(provider: provider, kind: kind, ref: ref, gone_at: nil).update_all(gone_at: Time.current, updated_at: Time.current)
end
