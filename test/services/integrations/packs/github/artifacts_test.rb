require "test_helper"
require "zip"

module Integrations
  module Packs
    class Github
      class ArtifactsTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "a run's artifacts are listed with their ids, sizes and whether they are kept" do
          GithubApp.expects(:get).with("/repos/acme/web/actions/runs/77/artifacts?per_page=20", token: "ghs_token").returns("artifacts" => [ artifact ])

          text = text_of(@pack.list_artifacts(environment_row: @row, arguments: { "repo" => "acme/web", "run_id" => 77 }))

          assert_includes text, "Artifacts in run 77 of acme/web, newest first:\n  test-report  id 9  2048 bytes  made 2026-10-12T09:00:00Z  " \
                                "kept until 2027-01-10T09:00:00Z  run 77 on main at #{'a' * 12}"
          assert text.end_with?("https://github.com/acme/web/actions/runs/77")

          GithubApp.expects(:get).with("/repos/acme/web/actions/artifacts?name=coverage&per_page=20", token: "ghs_token").returns("artifacts" => [])
          assert_includes text_of(@pack.list_artifacts(environment_row: @row, arguments: { "repo" => "acme/web", "name" => "coverage" })), "No artifacts in acme/web named coverage."
        end

        test "an artifact is read whole, its files listed and its text files shown, binary ones left out" do
          GithubApp.stubs(:get).with("/repos/acme/web/actions/artifacts/9", token: "ghs_token").returns(artifact)
          GithubApp.expects(:download).with("/repos/acme/web/actions/artifacts/9/zip", token: "ghs_token", limit: Artifacts::ARCHIVE_LIMIT, archive: true)
                   .returns(zipped("junit.xml" => "<testcase name=\"checkout\"><failure>timeout</failure></testcase>", "shot.png" => "\x89PNG\x00\x00binary"))

          text = text_of(@pack.read_artifact(environment_row: @row, arguments: { "repo" => "acme/web", "artifact_id" => 9 }))

          assert_includes text, "Files:\n  junit.xml  "
          assert_includes text, "  shot.png  "
          assert_includes text, "junit.xml:\n<testcase name=\"checkout\"><failure>timeout</failure></testcase>"
          assert_not_includes text, "binary"
        end

        test "an expired or large artifact is not downloaded" do
          GithubApp.expects(:download).never
          GithubApp.stubs(:get).with("/repos/acme/web/actions/artifacts/9", token: "ghs_token").returns(artifact.merge("expired" => true))
          assert_match "has expired", assert_raises(NativePack::Error) { @pack.read_artifact(environment_row: @row, arguments: { "repo" => "acme/web", "artifact_id" => 9 }) }.message

          GithubApp.stubs(:get).with("/repos/acme/web/actions/artifacts/10", token: "ghs_token").returns(artifact.merge("id" => 10, "size_in_bytes" => 50_000_000))
          error = assert_raises(PolicyRefusal) { @pack.read_artifact(environment_row: @row, arguments: { "repo" => "acme/web", "artifact_id" => 10 }) }
          assert_match "is 50000000 bytes, more than the #{Artifacts::ARCHIVE_LIMIT} Firefight reads", error.message
          assert Github.tool_definitions.select { |tool| %w[list_artifacts read_artifact].include?(tool.name) }.all?(&:read_only)
        end

        private

        def artifact
          { "id" => 9, "name" => "test-report", "size_in_bytes" => 2048, "expired" => false, "created_at" => "2026-10-12T09:00:00Z",
            "expires_at" => "2027-01-10T09:00:00Z", "workflow_run" => { "id" => 77, "head_branch" => "main", "head_sha" => "a" * 40 } }
        end

        def zipped(files)
          buffer = Zip::OutputStream.write_buffer do |zip|
            files.each do |name, content|
              zip.put_next_entry(name)
              zip.write(content)
            end
          end
          buffer.string.b
        end

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
