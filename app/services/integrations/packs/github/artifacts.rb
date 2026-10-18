module Integrations
  module Packs
    class Github
      # The files a workflow run uploaded (actions/list-workflow-run-artifacts, list-artifacts-for-repo, get-artifact and
      # download-artifact in github/rest-api-description), all Actions read. GitHub hands an artifact over as a zip
      # archive at a short-lived signed address, which is fetched like a job's log (GithubApp.download) but only when the
      # artifact is small enough to read whole, and only text files in it are shown, each cut short.
      module Artifacts
        # The most of an archive read, by the size GitHub gives before it is fetched.
        ARCHIVE_LIMIT = 10_000_000
        FILE_SHOWN = 4_000
        TEXT_SHOWN = 16_000
        FILES_LISTED = 50
        # A file with a zero byte in its first few thousand is taken for binary, as git does.
        SNIFF = 8_000

        def self.included(pack)
          pack.tool :list_artifacts,
                    summary: "Lists the artifacts a workflow run uploaded, such as test reports.",
                    description: "The files a GitHub Actions run uploaded as artifacts, such as test reports or build output, with each " \
                                 "one's id, size and whether it has expired. Without a run, the repository's newest, by name if given",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "run_id" => { "type" => "integer", "description" => "The run's id, as workflow_runs or ci_status shows it (optional)" },
                      "name" => { "type" => "string", "description" => "Only artifacts with this name, when no run is given (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{Asking::LIST_LIMIT}, at most #{Asking::MAX_LIST})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :read_artifact,
                    summary: "Shows the files inside a workflow artifact and the text of each.",
                    description: "Read a GitHub Actions artifact: the files in it, and the text of the text files, each cut short. " \
                                 "An artifact larger than #{ARCHIVE_LIMIT / 1_000_000} MB is not read",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "artifact_id" => { "type" => "integer", "description" => "The artifact's id, as list_artifacts shows it" },
                      "file" => { "type" => "string", "description" => "Only this file in the artifact, by its path in it (optional, every text file)" }
                    }, %w[repo artifact_id]),
                    read_only: true
        end

        def list_artifacts(environment_row:, arguments:)
          repo = repo_argument(arguments)
          run = (number_argument(arguments, "run_id") if arguments["run_id"].present?)
          name = arguments["name"].to_s.strip.presence
          token = GithubApp.installation_token(environment_row)
          asking("list_artifacts", run ? "GitHub has no run #{run} in #{repo}" : "GitHub found no repository #{repo}") do
            query = { "per_page" => limit_argument(arguments), "name" => (name unless run) }.compact.to_query
            path = run ? "/repos/#{repo}/actions/runs/#{run}/artifacts" : "/repos/#{repo}/actions/artifacts"
            artifacts = Array(GithubApp.get("#{path}?#{query}", token: token)["artifacts"])
            where = run ? "run #{run} of #{repo}" : repo
            text = artifacts.empty? ? "No artifacts in #{where}#{" named #{name}" if name && !run}." : "Artifacts in #{where}, newest first:\n#{artifacts.map { |artifact| artifact_line(artifact) }.join("\n")}"
            linked(text, run ? repo_page(repo, "actions/runs/#{run}") : repo_page(repo, "actions"))
          end
        end

        def read_artifact(environment_row:, arguments:)
          repo = repo_argument(arguments)
          id = number_argument(arguments, "artifact_id")
          only = arguments["file"].to_s.strip.delete_prefix("/").presence
          token = GithubApp.installation_token(environment_row)
          asking("read_artifact", "GitHub has no artifact #{id} in #{repo}") do
            artifact = GithubApp.get("/repos/#{repo}/actions/artifacts/#{id}", token: token)
            page = artifact.dig("workflow_run", "id") ? repo_page(repo, "actions/runs/#{artifact.dig('workflow_run', 'id')}") : repo_page(repo, "actions")
            fail! "Artifact #{artifact['name']} (#{id}) in #{repo} has expired, so GitHub no longer has its files." if artifact["expired"]
            if artifact["size_in_bytes"].to_i > ARCHIVE_LIMIT
              fail_policy! "Artifact #{artifact['name']} (#{id}) in #{repo} is #{artifact['size_in_bytes']} bytes, more than the #{ARCHIVE_LIMIT} Firefight reads. " \
                    "Its files are on the run's page, #{page}."
            end

            archive = GithubApp.download("/repos/#{repo}/actions/artifacts/#{id}/zip", token: token, limit: ARCHIVE_LIMIT, archive: true)
            linked("#{artifact_line(artifact).strip}\n\n#{archive_text(archive, only)}", page)
          end
        end

        private

        def artifact_line(artifact)
          run = artifact["workflow_run"].to_h
          "  #{artifact['name']}  id #{artifact['id']}  #{artifact['size_in_bytes']} bytes  made #{artifact['created_at']}  " \
            "#{artifact['expired'] ? 'expired' : "kept until #{artifact['expires_at']}"}#{"  run #{run['id']} on #{run['head_branch']} at #{run['head_sha'].to_s[0, 12]}" if run['id']}"
        end

        # Each entry is read only up to what is shown, so an archive whose files unpack far larger than it is reads no more.
        def archive_text(archive, only)
          require "zip"
          files = []
          Zip::File.open_buffer(StringIO.new(archive)) { |zip| zip.each { |entry| files << entry if entry.file? } }
          listed = files.first(FILES_LISTED).map { |entry| "  #{entry.name}  #{entry.size} bytes" }
          heading = "Files#{" (the first #{FILES_LISTED} of #{files.size})" if files.size > FILES_LISTED}:\n#{listed.join("\n")}"
          chosen = only ? files.select { |entry| entry.name == only } : files
          fail! "The artifact has no file #{only}. #{heading}" if only && chosen.empty?

          texts = []
          chosen.each do |entry|
            room = TEXT_SHOWN - texts.sum(&:length)
            break if room <= 0

            text = entry_text(entry)
            texts << "#{entry.name}:\n#{text.truncate([ FILE_SHOWN, room ].min)}" if text
          end
          [ heading, (texts.any? ? texts.join("\n\n") : "No text files to show.") ].join("\n\n")
        rescue Zip::Error => error
          fail! "GitHub's archive of the artifact could not be opened: #{error.message}."
        end

        def entry_text(entry)
          bytes = entry.get_input_stream { |stream| stream.read(FILE_SHOWN * 4) }.to_s
          return nil if bytes.byteslice(0, SNIFF).to_s.include?("\x00")

          bytes.dup.force_encoding(Encoding::UTF_8).scrub
        end
      end
    end
  end
end
