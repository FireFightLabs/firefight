module Integrations
  module Packs
    class Github
      # What changed before a time, across every repository the installation can see, found the way an engineer looks:
      # the repositories the clues point at, the files a stack trace runs through, the code that raises the error, and
      # every deploy and merge in the window before. Each search is bounded, and the answer says what it did not check.
      class ChangesBefore
        REPOSITORY_PAGES = 5
        TREE_LIMIT = 15
        CANDIDATE_LIMIT = 10
        TEXT_LIMIT = 3
        MERGE_DETAIL_LIMIT = 20
        DEPLOYMENT_CANDIDATES = 30
        SUSPECT_LIMIT = 15
        BLAME_LIMIT = 5
        BLAME_CONTEXT = 3
        SUMMARY_DAYS = 7
        PRODUCTION = /\Aprod/i
        # GitHub's commit search reads committer dates in this form.
        SEARCH_TIME = "%Y-%m-%dT%H:%M:%SZ".freeze

        Located = Data.define(:path, :line, :repository, :file)

        def initialize(token:, started:, window:, clues:)
          @token = token
          @started = started
          @window = window
          @since = started - window
          @clues = clues
          @unchecked = []
        end

        def text
          merges = merges_in_window
          candidates = candidate_repositories(merges)
          deploys = candidates.flat_map { |repository| deploys_of(repository) }
          deployed = deploys.map(&:sha).to_set
          # A merge that was then deployed is one change, and the deploy is the stronger evidence.
          changes = deploys.select { |change| change.at >= @since } +
                    merge_changes(merges, candidates).reject { |change| deployed.include?(change.sha) }
          ranking = CodeChange::Ranking.new(started: @started, window: @window, paths: located.map(&:file), places: places)

          [
            header,
            where_to_look(candidates),
            running_text(candidates, deploys),
            suspects_text(ranking.rank(changes)),
            after_start_text(changes),
            blame_text(deploys),
            summary_text,
            unchecked_text
          ].compact.join("\n\n")
        end

        private

        def get(path) = GithubApp.get(path, token: @token)

        def repositories
          @repositories ||= (1..REPOSITORY_PAGES).each_with_object({}) do |page, found|
            body = get("/installation/repositories?#{{ 'per_page' => 100, 'page' => page }.to_query}")
            Array(body["repositories"]).each { |repository| found[repository["full_name"]] = repository }
            break found if found.size >= body["total_count"].to_i

            @unchecked << "Only the first #{found.size} of #{body['total_count']} repositories were looked at." if page == REPOSITORY_PAGES
          end
        end

        def owners
          repositories.values.map { |repository| [ repository.dig("owner", "login"), repository.dig("owner", "type") ] }.uniq
        end

        # One search per owner finds every commit on every default branch in the window, whatever the repository.
        def merges_in_window
          range = "#{@since.utc.strftime(SEARCH_TIME)}..#{@started.utc.strftime(SEARCH_TIME)}"
          owners.flat_map do |login, type|
            scope = type == "Organization" ? "org" : "user"
            Array(get("/search/commits?#{{ 'q' => "#{scope}:#{login} committer-date:#{range}", 'per_page' => 100 }.to_query}")["items"])
          rescue GithubApp::Error => error
            @unchecked << "Commits by #{login} could not be searched: #{error.message}"
            []
          end
        end

        def places
          (Array(@clues["repositories"]) + Array(@clues["names"])).map { |clue| clue["value"] }
        end

        # Named first, then where the failing files live, then where the error text is written, then where things changed.
        def candidate_repositories(merges)
          named = repositories.keys.select { |name| places.any? { |place| matches_place?(name, place) } }
          touched = merges.map { |item| item.dig("repository", "full_name") }
          ordered = (named + located.map(&:repository) + text_hits.map(&:first) + touched).uniq & repositories.keys
          ordered = recently_pushed(@since) if ordered.empty?
          if ordered.size > CANDIDATE_LIMIT
            @unchecked << "Deploys were read for #{CANDIDATE_LIMIT} of #{ordered.size} candidate repositories."
          end
          ordered.first(CANDIDATE_LIMIT)
        end

        def matches_place?(repository, place)
          place = place.to_s.downcase
          short = repository.downcase.split("/").last
          place == repository.downcase || place == short || short.include?(place)
        end

        def recently_pushed(after)
          repositories.values.select { |repository| Time.zone.parse(repository["pushed_at"].to_s)&.>=(after) }
                      .sort_by { |repository| repository["pushed_at"].to_s }.reverse.map { |repository| repository["full_name"] }
        end

        # A container adds prefixes such as /app/ to paths, so a frame matches the repository file it ends with.
        def located
          @located ||= begin
            frames = Array(@clues["paths"])
            frames.empty? ? [] : locate(frames)
          end
        end

        def locate(frames)
          pool = (repositories.keys.select { |name| places.any? { |place| matches_place?(name, place) } } +
                  recently_pushed(Time.current - 30.days)).uniq
          @unchecked << "Stack trace files were looked for in #{TREE_LIMIT} of #{pool.size} repositories." if pool.size > TREE_LIMIT
          files_by_repository = pool.first(TREE_LIMIT).to_h { |name| [ name, tree(name) ] }

          frames.filter_map do |frame|
            path = frame["value"]
            match = files_by_repository.lazy.filter_map do |name, files|
              file = files.find { |candidate| path == candidate || path.end_with?("/#{candidate}") || candidate.end_with?("/#{path}") }
              [ name, file ] if file
            end.first
            Located.new(path: path, line: frame["line"], repository: match.first, file: match.last) if match
          end
        end

        def tree(repository)
          branch = repositories.dig(repository, "default_branch")
          body = get("/repos/#{repository}/git/trees/#{branch}?recursive=1")
          @unchecked << "The file list of #{repository} was too large for GitHub to return whole." if body["truncated"]
          Array(body["tree"]).filter_map { |entry| entry["path"] if entry["type"] == "blob" }
        rescue GithubApp::Error => error
          @unchecked << "Files in #{repository} could not be listed: #{error.message}"
          []
        end

        def text_hits
          @text_hits ||= Array(@clues["error_texts"]).first(TEXT_LIMIT).flat_map do |clue|
            owners.flat_map do |login, type|
              scope = type == "Organization" ? "org" : "user"
              query = "\"#{clue['value'].delete('"')}\" #{scope}:#{login}"
              Array(get("/search/code?#{{ 'q' => query, 'per_page' => 20 }.to_query}")["items"])
                .map { |item| [ item.dig("repository", "full_name"), item["path"], clue["value"] ] }
            rescue GithubApp::Error => error
              @unchecked << "The code could not be searched for \"#{clue['value']}\": #{error.message}"
              []
            end
          end
        end

        # Timed by when the deploy succeeded, not when it was asked for, since that is when the code started running. The
        # deploy just before the week is read too, so the first one in the week has something to be compared against.
        def deploys_of(repository)
          deployments = Array(get("/repos/#{repository}/deployments?#{{ 'per_page' => DEPLOYMENT_CANDIDATES }.to_query}"))
          production = deployments.select { |deployment| deployment["environment"].to_s.match?(PRODUCTION) }
          scoped = production.presence || deployments
          summary_since = @started - SUMMARY_DAYS.days
          recent, older = scoped.partition { |deployment| Time.zone.parse(deployment["created_at"].to_s)&.>=(summary_since) }
          read = recent + older.first(1)

          succeeded = read.filter_map { |deployment| succeeded(repository, deployment) }.sort_by(&:at)
          succeeded.each_with_index.map do |change, index|
            index.zero? ? change : with_files(repository, change, succeeded[index - 1])
          end
        rescue GithubApp::Error => error
          @unchecked << "Deploys of #{repository} could not be read: #{error.message}"
          []
        end

        def succeeded(repository, deployment)
          at = GithubApp.deployment_succeeded_at(repository, deployment["id"], token: @token)
          return nil unless at

          CodeChange::Ranking::Change.new(
            repository: repository, kind: CodeChange::Ranking::KIND_DEPLOY, sha: deployment["sha"],
            at: at, title: deployment["description"].presence,
            author: deployment.dig("creator", "login"), url: "https://github.com/#{repository}/commit/#{deployment['sha']}",
            pull_number: nil, files: nil, environment: deployment["environment"], rollback: false
          )
        end

        # What a deploy changed is everything between it and the deploy before. A deploy behind the one before is a rollback.
        def with_files(repository, change, previous)
          return change if change.at < @since || change.sha == previous.sha

          comparison = get("/repos/#{repository}/compare/#{previous.sha}...#{change.sha}")
          files = Array(comparison["files"]).map { |file| file["filename"] }
          title = change.title || Array(comparison["commits"]).last&.dig("commit", "message").to_s.lines.first&.strip
          change.with(files: files, title: title, rollback: comparison["status"] == "behind")
        rescue GithubApp::Error
          change
        end

        def merge_changes(merges, candidates)
          newest = merges.select { |item| candidates.include?(item.dig("repository", "full_name")) }
                         .sort_by { |item| item.dig("commit", "committer", "date").to_s }.reverse
          if newest.size > MERGE_DETAIL_LIMIT
            @unchecked << "Changed files were read for the newest #{MERGE_DETAIL_LIMIT} of #{newest.size} commits in the window."
          end
          newest.each_with_index.map do |item, index|
            repository = item.dig("repository", "full_name")
            files = index < MERGE_DETAIL_LIMIT ? commit_files(repository, item["sha"]) : nil
            CodeChange::Ranking::Change.new(
              repository: repository, kind: CodeChange::Ranking::KIND_MERGE, sha: item["sha"],
              at: Time.zone.parse(item.dig("commit", "committer", "date").to_s),
              title: item.dig("commit", "message").to_s.lines.first&.strip,
              author: item.dig("author", "login") || item.dig("commit", "author", "name"), url: item["html_url"],
              pull_number: nil, files: files, environment: nil, rollback: false
            )
          end
        end

        def commit_files(repository, sha)
          Array(get("/repos/#{repository}/commits/#{sha}")["files"]).map { |file| file["filename"] }
        rescue GithubApp::Error
          nil
        end

        def header
          started = @clues["started"] || {}
          estimate = started["estimated"] ? " This is an estimate, since no alert or report said when it began." : ""
          "Changes before #{@started.utc.iso8601}, when it started according to #{started['source'] || 'the time given'}." \
            "#{estimate} Detail covers the #{@window.inspect} before, the summary the #{SUMMARY_DAYS} days before."
        end

        def where_to_look(candidates)
          lines = []
          Array(@clues["repositories"]).each { |clue| lines << "  #{clue['value']} is named by #{clue['source']}" }
          Array(@clues["names"]).each { |clue| lines << "  \"#{clue['value']}\" is named by #{clue['source']}" }
          located.each { |found| lines << "  #{found.path}:#{found.line} from the stack trace is #{found.file} in #{found.repository}" }
          text_hits.each { |repository, path, text| lines << "  \"#{text}\" is written in #{repository} #{path}" }
          Array(@clues["commits"]).each { |clue| lines << "  commit #{clue['value']} is named by #{clue['source']}" }
          lines << "  Nothing pointed at a repository, so every repository with changes in the window was read." if lines.empty?
          "Where the clues point:\n#{lines.join("\n")}\nRepositories read: #{candidates.join(', ').presence || 'none'}."
        end

        def running_text(candidates, deploys)
          named_commits = Array(@clues["commits"]).map { |clue| clue["value"] }
          lines = candidates.map do |repository|
            last = deploys.select { |change| change.repository == repository && change.at <= @started }.max_by(&:at)
            if last
              rollback = last.rollback ? ", a rollback to an older commit" : ""
              "  #{repository}: #{last.sha}, from a deploy record (#{last.environment}, succeeded #{last.at.utc.iso8601}#{rollback})"
            else
              "  #{repository}: no deploy record before it started. Use running_commit for the tip of its default branch, as a guess."
            end
          end
          named_commits.each { |sha| lines << "  An alert named commit #{sha} as running. That is exact when it matches a repository above." }
          "What was running:\n#{lines.join("\n")}"
        end

        def suspects_text(suspects)
          return "No deploy or merge in the window before it started. Look past code: traffic, dependencies, infrastructure, or an older change the failing lines show." if suspects.empty?

          shown = suspects.first(SUSPECT_LIMIT).each_with_index.map do |suspect, index|
            change = suspect.change
            "#{index + 1}. #{change.repository} #{change.kind} #{change.sha.to_s[0, 12]} at #{change.at.utc.iso8601} " \
              "by #{change.author || 'unknown'}: #{change.title}\n   Why: #{suspect.reasons.join('; ')}.\n   #{change.url}"
          end
          more = suspects.size > SUSPECT_LIMIT ? "\n#{suspects.size - SUSPECT_LIMIT} more changes rank below these." : ""
          "Suspects, most likely first. The reasons are the ranking, so weigh them yourself:\n#{shown.join("\n")}#{more}\n" \
            "compare_commits shows any change in full."
        end

        def after_start_text(changes)
          after = changes.select { |change| change.at > @started }
          return nil if after.empty?

          "After it started, so not a cause unless the start time is wrong:\n" +
            after.map { |change| "  #{change.repository} #{change.kind} #{change.sha.to_s[0, 12]} at #{change.at.utc.iso8601}" }.join("\n")
        end

        # When the failing lines last changed, whatever the window, which is how an old change hit by new traffic is found.
        def blame_text(deploys)
          return nil if located.empty?

          lines = located.first(BLAME_LIMIT).map do |found|
            running = deploys.select { |change| change.repository == found.repository && change.at <= @started }.max_by(&:at)&.sha
            ranges = GithubApp.blame(found.repository, found.file, running || "HEAD", token: @token)
            from = [ found.line - BLAME_CONTEXT, 1 ].max
            to = found.line + BLAME_CONTEXT
            touching = ranges.select { |range| range["startingLine"] <= to && range["endingLine"] >= from }
            described = touching.map do |range|
              commit = range["commit"]
              pull = commit.dig("associatedPullRequests", "nodes", 0)
              "#{commit['oid'][0, 12]} #{commit['committedDate']} #{commit['messageHeadline']}#{" PR ##{pull['number']}" if pull}"
            end
            "  #{found.repository} #{found.file}:#{found.line} at #{running ? running[0, 12] : 'the default branch'}: #{described.join('; ')}"
          rescue GithubApp::Error => error
            "  #{found.repository} #{found.file}:#{found.line}: could not blame, #{error.message}"
          end
          "When the failing lines last changed, however long ago:\n#{lines.join("\n")}"
        end

        def summary_text
          pushed = recently_pushed(@started - SUMMARY_DAYS.days)
          return "Nothing was pushed to any repository in the #{SUMMARY_DAYS} days before." if pushed.empty?

          lines = pushed.first(CANDIDATE_LIMIT).map { |name| "  #{name}: last push #{repositories.dig(name, 'pushed_at')}" }
          more = pushed.size > CANDIDATE_LIMIT ? "\n  #{pushed.size - CANDIDATE_LIMIT} more repositories were pushed to." : ""
          "Pushed to in the #{SUMMARY_DAYS} days before, for a slow burn:\n#{lines.join("\n")}#{more}"
        end

        def unchecked_text
          notes = @unchecked + [ "Config, feature flag and infrastructure changes made outside git are not checked." ]
          "Not checked:\n#{notes.uniq.map { |note| "  #{note}" }.join("\n")}"
        end
      end
    end
  end
end
