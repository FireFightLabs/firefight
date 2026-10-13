require "test_helper"

class CodeAgent::CallKindTest < ActiveSupport::TestCase
  Call = FirefightAi::ModelProxy::Calls::Call

  test "a call is what its tools did, in the order first seen" do
    calls = [ Call.new(name: "grep", input: {}), Call.new(name: "read", input: {}), Call.new(name: "glob", input: {}), Call.new(name: "edit", input: {}) ]

    assert_equal [ CodeAgent::CallKind::SEARCH, CodeAgent::CallKind::READ, CodeAgent::CallKind::EDIT ], CodeAgent::CallKind.of(calls)
    assert_equal [ CodeAgent::CallKind::ANSWER ], CodeAgent::CallKind.of([])
  end

  test "a command is read by what it runs, a test whatever else it chains" do
    {
      "cd app && rg -n needle" => CodeAgent::CallKind::SEARCH,
      "sed -n 1,80p app/models/user.rb" => CodeAgent::CallKind::READ,
      "git log --oneline -5" => CodeAgent::CallKind::SEARCH,
      "git diff HEAD~1" => CodeAgent::CallKind::READ,
      "git commit -m 'Fix'" => CodeAgent::CallKind::GIT,
      "RAILS_ENV=test bin/rails test test/models/user_test.rb" => CodeAgent::CallKind::TEST,
      "bundle install && bundle exec rspec spec/user_spec.rb" => CodeAgent::CallKind::TEST,
      "npm install" => CodeAgent::CallKind::SHELL,
      "" => CodeAgent::CallKind::SHELL
    }.each { |command, kind| assert_equal kind, CodeAgent::CallKind.kind("bash", { "command" => command }), command }
  end

  test "Firefight's own tools are known by the name the agent's server gives them" do
    assert_equal CodeAgent::CallKind::LOOKUP, CodeAgent::CallKind.kind("firefight_#{CodeAgent::ReadTools::CALL}", {})
    assert_equal CodeAgent::CallKind::LOOKUP, CodeAgent::CallKind.kind("firefight_#{Chat::Tools::Docs::SEARCH}", {})
    assert_equal CodeAgent::CallKind::QUESTION, CodeAgent::CallKind.kind("firefight_#{CodeAgent::QuestionTools::ASK}", {})
    assert_equal CodeAgent::CallKind::WEB, CodeAgent::CallKind.kind("firefight_#{Chat::Tools::Web::SEARCH}", {})
    assert_equal CodeAgent::CallKind::OTHER, CodeAgent::CallKind.kind("something_new", {})
  end
end
