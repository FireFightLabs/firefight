# Reads a reply repeats while it gets ready, such as the models the workspace names and the AI accounts that can pay,
# read once for as long as the runner holds them (Conversation::Runner), and what a workflow's canvas asks of each step
# and tool for its header, its steps and its tools list, held for one visit of the canvas. They are kept on this
# workspace instance and nowhere else, so a reply never sees what another read, and a read made while nothing holds them
# is read as ever. A reply stops holding them before the model works, since what its tools and its calls change is then
# read again. Nothing that is billed or that a billing write reads is held, so the credit a call is charged to stays
# exact.
module Workspace::HeldReads
  extend ActiveSupport::Concern

  def hold_reads! = @held_reads = {}

  def release_reads! = @held_reads = nil

  # What the block answers, read once while the reads are held, and every time otherwise.
  def read_held(key)
    held = @held_reads
    return yield unless held

    held.fetch(key) { held[key] = yield }
  end

  # For a write that makes what was read stale while the reads are held.
  def forget_held_read(key) = @held_reads&.delete(key)

  # The workspace's override of the model for a purpose, or for any purpose, the purpose's own first. The workspace's
  # overrides are few, so they are read together.
  def ai_model_override_for(purpose)
    overrides = read_held(:ai_model_overrides) { AiModelOverride.where(workspace_id: id).to_a }
    overrides.select { |row| row.purpose == purpose || row.purpose == AiPurpose::ANY }.min_by { |row| row.purpose == purpose ? 0 : 1 }
  end

  # Whether the workspace names a model for exactly this purpose, not counting an override for any purpose.
  def ai_model_override_named_for?(purpose)
    read_held(:ai_model_overrides) { AiModelOverride.where(workspace_id: id).to_a }.any? { |row| row.purpose == purpose }
  end

  # The AI accounts that can pay, in the order they are tried.
  def usable_ai_accounts = read_held(:usable_ai_accounts) { workspace_ai_accounts.usable.to_a }
end
