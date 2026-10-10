module Operator
  # Every code sandbox and kept copy across providers against the app's records, and the operator's stop, delete, adopt
  # and clean up, each asked first on the page, said in a toast and recorded with who did it.
  class SandboxesController < BaseController
    def index
      sandboxes = Sandboxes.new
      render inertia: "operator/sandboxes/index", props: {
        totals: SandboxTotalsSerializer.one(sandboxes.totals),
        reads: sandboxes.reads.map { |read| camelized(read).merge("readAt" => read.read_at&.utc&.iso8601) },
        boxes: SandboxBoxSerializer.many(sandboxes.boxes),
        copies: SandboxCopySerializer.many(sandboxes.copies),
        actions: SandboxActionSerializer.many(SandboxAction.order(created_at: :desc).limit(20)),
        windowStart: sandboxes.window_start.utc.iso8601,
        now: Time.current.utc.iso8601,
        cleanUpBlockedReason: Actions.clean_up_blocked_reason(sandboxes)
      }
    end

    def stop
      box = Sandboxes.new.box_at(params[:provider], params[:ref])
      act(SandboxAction::STOP, ProviderSandbox::KIND_BOX, Actions.sandbox_stop_blocked_reason(box), "Stopping #{box&.name || params[:ref]}.") do
        Integrations::SandboxInventory.stop!(box.provider, box.ref)
      end
    end

    def adopt
      box = Sandboxes.new.box_at(params[:provider], params[:ref])
      blocked = Actions.sandbox_adopt_blocked_reason(box)
      said = blocked ? nil : "Adopted #{box.name || box.ref} for #{box.claim.workspace.name}. It stops once nothing uses it for #{CodeBox::ABANDONED_AFTER.inspect}."
      act(SandboxAction::ADOPT, ProviderSandbox::KIND_BOX, blocked, said) do
        Integrations::SandboxInventory.adopt!(box.provider, box.ref, workspace: box.claim.workspace, key: box.claim.key, since: box.claim.since, size: box.size)
      end
    end

    def destroy
      kind = params[:kind] == ProviderSandbox::KIND_SNAPSHOT ? ProviderSandbox::KIND_SNAPSHOT : ProviderSandbox::KIND_BOX
      sandboxes = Sandboxes.new
      target = kind == ProviderSandbox::KIND_BOX ? sandboxes.box_at(params[:provider], params[:ref]) : sandboxes.copy_at(params[:provider], params[:ref])
      blocked = kind == ProviderSandbox::KIND_BOX ? Actions.sandbox_delete_blocked_reason(target) : Actions.copy_delete_blocked_reason(target)
      act(SandboxAction::DELETE, kind, blocked, "Deleted #{params[:ref]} for good.") do
        Integrations::SandboxInventory.delete!(target.provider, kind, target.ref)
      end
    end

    # Deletes every rogue box and kept copy for good.
    def clean_up
      sandboxes = Sandboxes.new
      blocked = Actions.clean_up_blocked_reason(sandboxes)
      return redirect_to(operator_sandboxes_path, alert: blocked) if blocked

      failed = sandboxes.rogue.filter_map do |each|
        kind = each.is_a?(Sandboxes::Box) ? ProviderSandbox::KIND_BOX : ProviderSandbox::KIND_SNAPSHOT
        Integrations::SandboxInventory.delete!(each.provider, kind, each.ref)
        record(SandboxAction::CLEAN_UP, each.provider, kind, each.ref)
        nil
      rescue Integrations::Error => error
        record(SandboxAction::CLEAN_UP, each.provider, kind, each.ref, outcome: error.message)
        "#{each.ref}: #{error.message}"
      end
      count = sandboxes.rogue.size - failed.size
      return redirect_to(operator_sandboxes_path, notice: "Deleted #{count} rogue #{'sandbox'.pluralize(count)} and copies.") if failed.empty?

      redirect_to operator_sandboxes_path, alert: "Deleted #{count}, and #{failed.size} could not be deleted. #{failed.first}"
    end

    private

    def act(action, kind, blocked, said)
      return redirect_to(operator_sandboxes_path, alert: blocked) if blocked

      yield
      record(action, params[:provider], kind, params[:ref])
      redirect_to operator_sandboxes_path, notice: said
    rescue Integrations::Error => error
      record(action, params[:provider], kind, params[:ref], outcome: error.message)
      redirect_to operator_sandboxes_path, alert: error.message
    end

    def record(action, provider, kind, ref, outcome: nil)
      SandboxAction.create!(action: action, provider: provider, kind: kind, ref: ref, operator: operator_label, outcome: outcome)
    end
  end
end
