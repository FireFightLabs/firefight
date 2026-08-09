module Integrations
  module Packs
    # First-party GitHub pack: PR and commit correlation over the REST API
    # with server-to-server installation tokens. Clone-backed tools
    # (fetch_file, code_search, blame) arrive with the clone manager.
    class Github < NativePack
      REPO_FORMAT = /\A[\w.\-]+\/[\w.\-]+\z/
      FILE_LIMIT = 30

      tool :pr_lookup,
           description: "Fetch a pull request: title, state, author, merge status, and changed files",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "number" => { "type" => "integer", "description" => "Pull request number" }
             },
             "required" => [ "repo", "number" ]
           },
           read_only: true

      tool :commit_lookup,
           description: "Fetch a commit: message, author, stats, and changed files",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "sha" => { "type" => "string", "description" => "Commit SHA" }
             },
             "required" => [ "repo", "sha" ]
           },
           read_only: true

      def self.install_url(state:)
        GithubApp.install_url(state: state)
      end

      def pr_lookup(environment_row:, arguments:)
        repo = repo_argument(arguments)
        number = Integer(arguments["number"].to_s, exception: false)
        raise NativePack::Error, "number must be an integer" unless number

        token = GithubApp.installation_token(environment_row)
        pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
        files = GithubApp.get("/repos/#{repo}/pulls/#{number}/files?per_page=#{FILE_LIMIT}", token: token)

        <<~TEXT
          PR ##{pull['number']}: #{pull['title']}
          State: #{pull['merged_at'] ? "merged at #{pull['merged_at']}" : pull['state']}
          Author: #{pull.dig('user', 'login')}
          Branch: #{pull.dig('head', 'ref')} -> #{pull.dig('base', 'ref')}
          Changes: #{pull['changed_files']} files, +#{pull['additions']} -#{pull['deletions']}

          #{file_lines(files, pull['changed_files'])}
          #{pull['body'].presence || '(no description)'}
        TEXT
      end

      def commit_lookup(environment_row:, arguments:)
        repo = repo_argument(arguments)
        sha = arguments["sha"].to_s
        raise NativePack::Error, "sha must be a commit SHA" unless sha.match?(/\A\h{6,40}\z/)

        token = GithubApp.installation_token(environment_row)
        commit = GithubApp.get("/repos/#{repo}/commits/#{sha}", token: token)

        <<~TEXT
          Commit #{commit['sha']}
          Author: #{commit.dig('commit', 'author', 'name')} at #{commit.dig('commit', 'author', 'date')}
          Changes: +#{commit.dig('stats', 'additions')} -#{commit.dig('stats', 'deletions')}

          #{commit.dig('commit', 'message')}

          #{file_lines(commit['files'], commit['files']&.size)}
        TEXT
      end

      def check_health!(environment_row)
        GithubApp.installation_token(environment_row)
      end

      private

      def repo_argument(arguments)
        repo = arguments["repo"].to_s
        raise NativePack::Error, "repo must be in owner/name form" unless repo.match?(REPO_FORMAT)

        repo
      end

      def file_lines(files, total)
        listed = Array(files).first(FILE_LIMIT)
        lines = listed.map { |file| "  #{file['filename']} (+#{file['additions']} -#{file['deletions']})" }
        lines << "  ... #{total.to_i - listed.size} more files" if total.to_i > listed.size
        lines.join("\n")
      end
    end
  end
end
