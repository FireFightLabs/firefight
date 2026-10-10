require "test_helper"

class Conversation::BenchToolsTest < ActiveSupport::TestCase
  # A tool changed on its own side and not here means the bench offers Halon the old one. bin/rails halon:bench_tools
  # copies it again.
  test "every shared tool marked live matches what a chat is offered today" do
    drift = Conversation::BenchTools.drift

    assert_empty drift, drift.map { |name, fields| "#{name}: #{fields.join(', ')} differ, run bin/rails halon:bench_tools" }.join("\n")
  end

  test "a changed description, schema or way of asking is named by the tool, and one no longer offered too" do
    snapshot = {
      "start_watch" => { "live" => true, "description" => "Old words.", "parameters" => { "type" => "object", "properties" => {} } },
      "gone_tool" => { "live" => true, "description" => "Gone." },
      "northflank_api_request" => { "description" => "Written here." }
    }
    offered = { "start_watch" => { "description" => "New words.", "parameters" => { "type" => "object", "properties" => {} }, "confirms" => true } }

    assert_equal({ "start_watch" => %w[description confirms], "gone_tool" => [ "no longer offered" ] }, Conversation::BenchTools.drift(snapshot, offered))
  end

  test "the refresh copies each live tool's fields and keeps what the bench sets itself" do
    path = Rails.root.join("tmp/bench_tools_#{SecureRandom.hex(4)}.yml")
    File.write(path, { "start_watch" => { "live" => true, "description" => "Old words.", "default" => "Watching.", "parameters" => {} },
                       "search_handbook" => { "description" => "Written here.", "reads" => true } }.to_yaml)

    assert_equal [ "start_watch" ], Conversation::BenchTools.refresh!(path)
    written = YAML.safe_load_file(path)

    assert_equal Conversation::BenchTools.live["start_watch"]["description"], written["start_watch"]["description"]
    assert_equal [ "Watching.", true ], written["start_watch"].values_at("default", "live")
    assert_equal({ "description" => "Written here.", "reads" => true }, written["search_handbook"])
    assert File.read(path).start_with?(Conversation::BenchTools::HEADER)
  ensure
    FileUtils.rm_f(path)
  end
end
