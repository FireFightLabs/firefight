require "test_helper"

# What a reply reads again and again while it gets ready is read once, on its own workspace, until it stops holding it.
class Workspace::HeldReadsTest < ActiveSupport::TestCase
  include QueryCountHelper

  setup do
    @workspace = Workspace.find(workspaces(:slack_workspace_one).id)
    @first = add_ai_account!(@workspace, provider: "openai", key: "sk-own-first", label: "First")
    @second = add_ai_account!(@workspace, provider: "openai", key: "sk-own-second", label: "Second")
  end

  test "reads as ever while nothing holds them" do
    sent = ActiveRecord::Base.uncached { queries_sent { 3.times { @workspace.usable_ai_accounts } } }

    assert_equal 3, sent.size
  end

  test "reads once while held, and again once released" do
    @workspace.hold_reads!
    held = ActiveRecord::Base.uncached { queries_sent { 3.times { @workspace.usable_ai_accounts } } }
    @workspace.release_reads!
    released = ActiveRecord::Base.uncached { queries_sent { 2.times { @workspace.usable_ai_accounts } } }

    assert_equal 1, held.size
    assert_equal 2, released.size
  end

  test "holds nothing for another instance of the same workspace" do
    @workspace.hold_reads!
    other = Workspace.find(@workspace.id)

    sent = ActiveRecord::Base.uncached { queries_sent { 2.times { other.usable_ai_accounts } } }

    assert_equal 2, sent.size
  end

  test "an account that ran dry while the reads are held is no longer offered" do
    @workspace.hold_reads!
    assert_equal [ @first.id, @second.id ], @workspace.usable_ai_accounts.map(&:id)

    @workspace.usable_ai_accounts.first.ran_out!(StandardError.new("out of credit"))

    assert_equal [ @second.id ], @workspace.usable_ai_accounts.map(&:id)
  end

  test "the model an override names is the purpose's own before the one for any purpose, read once while held" do
    @workspace.ai_model_overrides.create!(purpose: AiPurpose::ANY, model: "gpt-4o", provider: "openai")
    @workspace.ai_model_overrides.create!(purpose: AiPurpose::SUMMARY, model: "gpt-4o-mini", provider: "openai")
    @workspace.hold_reads!

    sent = ActiveRecord::Base.uncached do
      queries_sent do
        assert_equal "gpt-4o-mini", @workspace.ai_model_override_for(AiPurpose::SUMMARY).model
        assert_equal "gpt-4o", @workspace.ai_model_override_for(AiPurpose::INVESTIGATION).model
        assert_equal "gpt-4o", @workspace.ai_model_override_for(AiPurpose::POSTMORTEM).model
      end
    end

    assert_equal 1, sent.size
  end

  test "no override is nil" do
    assert_nil @workspace.ai_model_override_for(AiPurpose::SUMMARY)
  end

  test "the credit a call is charged to is read every time, held or not" do
    credit = stub(spendable?: true)
    Entitlements.stubs(:ai_account).returns("other")
    Entitlements.stubs(:firefight_pays_for_ai?).returns(false)
    Entitlements.expects(:ai_credit).with(@workspace).times(3).returns(credit)
    @workspace.hold_reads!

    3.times { AiFunding.for(@workspace, AiPurpose::INVESTIGATION) }
  end
end
