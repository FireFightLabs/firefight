require "test_helper"

module Integrations
  class SandboxInventoryTest < ActiveSupport::TestCase
    class HoldingProvider < Sandboxes::Provider
      attr_accessor :held
      attr_reader :stopped, :deleted, :discarded

      def initialize
        @held = []
        @stopped = []
        @deleted = []
        @discarded = []
      end

      def running = []

      def inventory = @held

      def stop(ref) = @stopped << ref

      def delete(ref) = @deleted << ref

      def discard(ref) = @discarded << ref
    end

    setup do
      @workspace = workspaces(:slack_workspace_one)
      @provider = HoldingProvider.new
      Sandboxes.stubs(:provider).returns(@provider)
      SandboxProviders.stubs(:in_use).returns([ SandboxProviders::BOAT ])
    end

    test "what a provider holds is recorded on every reading, and what it stopped holding is marked gone" do
      @provider.held = [ held("bx_1"), held("bx_2") ]
      SandboxInventory.record!
      @provider.held = [ held("bx_2", state: "archived", phase: ProviderSandbox::PHASE_STOPPED) ]
      SandboxInventory.record!

      assert ProviderSandbox.find_by!(ref: "bx_1").gone_at
      kept = ProviderSandbox.find_by!(ref: "bx_2")
      assert_nil kept.gone_at
      assert_equal [ "archived", ProviderSandbox::PHASE_STOPPED ], [ kept.state, kept.phase ]
      assert_nil SandboxProviderRead.find_by!(provider: SandboxProviders::BOAT).error
    end

    test "a provider that cannot be read keeps what it last held and says why" do
      @provider.held = [ held("bx_1") ]
      SandboxInventory.record!
      @provider.stubs(:inventory).raises(Sandboxes::Error, "boat.dev answered 401: Provide a valid bearer token. (unauthorized)")

      SandboxInventory.record!

      assert_nil ProviderSandbox.find_by!(ref: "bx_1").gone_at
      assert_equal "boat.dev answered 401: Provide a valid bearer token. (unauthorized)", SandboxProviderRead.find_by!(provider: SandboxProviders::BOAT).error
    end

    test "stopping or deleting a box a run holds closes its row first, and deleting a copy removes its row" do
      box = CodeBox.create!(workspace: @workspace, key: "investigation-1", provider: SandboxProviders::BOAT, box_ref: "bx_1", address: "https://a",
                            secret: "k", last_used_at: Time.current)
      kept = PreparedCopy.kept!(SandboxProviders::BOAT, @workspace, "acme/app", "key-1", kept_ref: "halon-kept-1", commit: "abc").first

      SandboxInventory.stop!(SandboxProviders::BOAT, "bx_1")
      SandboxInventory.delete!(SandboxProviders::BOAT, ProviderSandbox::KIND_SNAPSHOT, "halon-kept-1")

      assert box.reload.stopped_at
      assert_equal [ "bx_1" ], @provider.stopped
      assert_equal [ "halon-kept-1" ], @provider.discarded
      assert_not PreparedCopy.exists?(kept.id)
    end

    private

    def held(ref, state: "idle", phase: ProviderSandbox::PHASE_RUNNING)
      Sandboxes::Held.new(kind: ProviderSandbox::KIND_BOX, ref: ref, name: "halon-box-#{ref}", state: state, phase: phase, started_at: 1.hour.ago)
    end
  end
end
