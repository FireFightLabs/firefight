require "test_helper"
require "rake"

class ProviderDocsRakeTest < ActiveSupport::TestCase
  INDEX = "https://docs.example.com/llms.txt".freeze
  PAGE = "https://docs.example.com/v1/workflows.md".freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("provider_docs:sync")
    Rake::Task["provider_docs:sync"].reenable
    @definitions = [ definition("northflank_docs"), definition("northflank_skills") ]
    ProviderDocSource::Definition.stubs(:all).returns(@definitions)
    Chat::Skill.stubs(:missing_references).returns({})
    @web = FakeWeb.new(INDEX => "- [workflows](#{PAGE})", PAGE => "# Workflows\n\n## Webhook\n\nCopy the URL.")
    DocsClient.stubs(:new).returns(@web)
    FirefightAi.stubs(:embed_documents).returns([ [ Array.new(ProviderDocChunk::DIMENSIONS, 0.1) ], FirefightAi.embedding_model ])
  end

  teardown do
    ENV.delete("SOURCE")
    ENV.delete("UNREAD")
  end

  test "reads one source now and prints each step as a plain line" do
    ENV["SOURCE"] = "northflank_docs"

    output, = capture_io { Rake::Task["provider_docs:sync"].invoke }

    lines = output.lines(chomp: true)
    assert_equal "Reading 1 source", lines.first
    assert_includes lines, "northflank_docs  reading 1 page"
    assert_match(/\Anorthflank_docs  done, 1 page, 1 chunk written in \d+s\z/, lines.find { |line| line.include?("done") })
    assert_includes lines, "Embedding 1 chunk"
    assert_match(/\ADone in \d+s: 1 source read, 1 page, 1 chunk written, 1 embedded\z/, lines.last)
    assert ProviderDocSource.find_by!(key: "northflank_docs").fetched_at
    assert_nil ProviderDocSource.find_by(key: "northflank_skills")
  end

  test "UNREAD=1 reads only the sources never read, and says so when there are none" do
    ProviderDocSource.create!(key: "northflank_docs", provider: "northflank", fetched_at: Time.current)
    ENV["UNREAD"] = "1"

    output, = capture_io { Rake::Task["provider_docs:sync"].invoke }
    assert_includes output, "Reading 1 source\n"
    assert_includes output, "northflank_skills  reading 1 page\n"
    assert_not_includes output, "northflank_docs  "

    Rake::Task["provider_docs:sync"].reenable
    output, = capture_io { Rake::Task["provider_docs:sync"].invoke }
    assert_equal "Every source has been read already.\n", output
  end

  test "an unknown source names the ones there are" do
    ENV["SOURCE"] = "nope"

    _output, error = capture_io { assert_raises(SystemExit) { Rake::Task["provider_docs:sync"].invoke } }

    assert_includes error, "No source named nope. Sources: northflank_docs, northflank_skills"
  end

  private

  def definition(key)
    ProviderDocSource::Definition.new(key: key, provider: "northflank", kind: "index",
                                      settings: { "index" => INDEX, "under" => "https://docs.example.com/v1/", "suffix" => ".md", "to" => key })
  end
end
