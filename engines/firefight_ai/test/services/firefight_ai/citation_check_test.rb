require "test_helper"

class FirefightAi::CitationCheckTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @check = FirefightAi::CitationCheck.new(@workspace, inferable: @incident)
    @claims = [
      FirefightAi::CitationCheck::Claim.new(number: 1, text: "The controller calls require_admin!", steps: [ 3 ]),
      FirefightAi::CitationCheck::Claim.new(number: 2, text: "The billing tables are missing in production", steps: [ 5 ])
    ]
    @sources = [
      FirefightAi::CitationCheck::Source.new(step: 3, tool: "github_fetch_file", text: "before_action :require_admin!"),
      FirefightAi::CitationCheck::Source.new(step: 5, tool: "planetscale_execute_read_query", text: "billing_schema_exists: true")
    ]
  end

  test "each claim comes back with whether its cited results show it and why" do
    stub_model([
      { number: 1, shown: true, reason: "step 3 has the before_action" },
      { number: 2, shown: false, reason: "step 5 says the schema exists" }
    ])

    verdicts = @check.check(claims: @claims, sources: @sources)

    assert_equal [ true, false ], verdicts.map(&:shown)
    assert_equal "step 5 says the schema exists", verdicts.last.reason
  end

  test "the results are handed over as evidence, framed and numbered, never as instructions" do
    asked = nil
    stub_model([]) { |prompt| asked = prompt }

    @check.check(claims: @claims, sources: @sources)

    assert_includes asked, FirefightAi::Evidence.frame("github_fetch_file", "before_action :require_admin!", step: 3)
    assert_includes asked, "1. The controller calls require_admin! (cites step 3)"
  end

  test "a claim the model did not judge, or judged under a number that was never asked, is left out" do
    stub_model([ { number: 7, shown: false, reason: "no such claim" } ])

    assert_empty @check.check(claims: @claims, sources: @sources)
  end

  test "nothing to check makes no call" do
    RubyLLM.expects(:chat).never

    assert_empty @check.check(claims: [], sources: [])
  end

  private

  def stub_model(rows, &capture)
    response = llm_reply(content: { "claims" => rows }, input: 100, output: 50, cost: 0.0001)
    chat = mock("chat")
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_schema).returns(chat)
    if capture
      chat.stubs(:ask).with { |prompt| capture.call(prompt); true }.returns(response)
    else
      chat.stubs(:ask).returns(response)
    end
    RubyLLM.stubs(:chat).returns(chat)
  end
end
