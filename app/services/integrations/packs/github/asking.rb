module Integrations
  module Packs
    class Github
      # What the tools for pull requests, issues, releases, branches, checks and security alerts share: the numbers,
      # names and text they take, the page each answer links, and GitHub's refusals said in words a person acts on.
      # Every path is under /repos/{owner}/{repo}, so GitHub answers only for a repository the installation was given,
      # which is how a connection's repository selection holds.
      module Asking
        LIST_LIMIT = 20
        MAX_LIST = 100
        # GitHub keeps an issue's, a pull request's and a comment's body to 65,536 characters (docs.github.com, REST API,
        # Issues, Create an issue comment, which refuses a longer one with 422).
        BODY_LIMIT = 65_536
        TITLE_LIMIT = 256
        # A GitHub login: letters, digits and single hyphens, at most 39, and an app's bot account with [bot] after it.
        LOGIN = /\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})(\[bot\])?\z/
        TEAM = /\A[\w.-]+\z/
        SHOWN_TEXT = 1_500
        PROVIDER = GithubApp::PROVIDER
        GRANT_WHERE = "An owner of the GitHub account grants it under Settings, GitHub Apps, by accepting the App's new permissions".freeze
        NOT_GIVEN = "GitHub answers not found for a repository this connection's GitHub App was not given, and list_repositories names the ones it was".freeze

        private

        # The call to GitHub, with a permission the App lacks named as GitHub's App settings name it, and something that is
        # not there said with absent and why it may be.
        def asking(tool, absent)
          yield
        rescue GithubApp::NotPermitted => error
          fail! Sentence.join("GitHub refused this", error, after: "#{Github.needs_sentence(tool)} #{GRANT_WHERE}")
        rescue GithubApp::NotFound
          fail! Sentence.all("#{absent}.", NOT_GIVEN)
        end

        # A read that only adds to an answer: what it found, or a line saying why it is not shown.
        def adding(what, permission)
          yield
        rescue GithubApp::NotPermitted
          "#{what} not shown: Firefight's GitHub App needs #{permission} for them."
        rescue GithubApp::NotFound
          "#{what}: none."
        rescue GithubApp::Error => error
          Sentence.join("#{what} could not be read", error)
        end

        def number_argument(arguments, key = "number")
          number = Integer(arguments[key].to_s, exception: false)
          fail! "#{key} must be a whole number" unless number&.positive?

          number
        end

        # Text Firefight writes on GitHub, where a repository can be public, so anything that looks like a credential is
        # replaced first.
        def written_text(arguments, key, required: true, limit: BODY_LIMIT)
          value = arguments[key].to_s.strip
          fail! "#{key} is required" if value.empty? && required
          return nil if value.empty?
          fail! "#{key} is longer than GitHub takes, #{limit} characters" if value.length > limit

          Chat::SecretFree.redacted(value)
        end

        # A list given as a list or as one comma separated text, each one stripped and given once.
        def names_argument(arguments, key)
          given = arguments[key]
          listed = given.is_a?(Array) ? given : given.to_s.split(",")
          listed.map { |name| name.to_s.strip }.reject(&:empty?).uniq
        end

        def logins_argument(arguments, key)
          names_argument(arguments, key).map { |name| name.delete_prefix("@") }.each do |login|
            fail! "#{login} in #{key} is not a GitHub login" unless login.match?(LOGIN)
          end
        end

        def login_argument(arguments, key)
          login = arguments[key].to_s.strip.delete_prefix("@")
          return nil if login.empty?
          fail! "#{key} must be a GitHub login" unless login.match?(LOGIN)

          login
        end

        def choice_argument(arguments, key, choices, default: nil)
          value = arguments[key].to_s.strip.downcase.presence || default
          fail! "#{key} must be one of #{choices.join(', ')}" unless value.nil? || choices.include?(value)

          value
        end

        def limit_argument(arguments, default = LIST_LIMIT) = whole_number_argument(arguments, "limit", default, MAX_LIST)

        def boolean_argument(arguments, key) = ActiveModel::Type::Boolean.new.cast(arguments[key]) || false

        def github_link(url) = url.present? ? Telemetry::Link.new(provider: PROVIDER, url: url) : nil

        def linked(text, url) = Telemetry.result(text, link: github_link(url))

        # A page under the repository's address as GitHub's documentation names it, such as /pulls, /issues, /releases,
        # /branches, /commit/<sha> or /security/dependabot, for an answer that lists rather than names one thing.
        def repo_page(repo, rest = nil) = "https://github.com/#{repo}#{"/#{rest}" if rest}"

        def default_branch(repo, token) = GithubApp.get("/repos/#{repo}", token: token)["default_branch"]

        def shown(text, limit = SHOWN_TEXT) = text.to_s.strip.truncate(limit).presence

        def login_of(item) = item.dig("user", "login") || "unknown"

        def label_names(item) = Array(item["labels"]).filter_map { |label| label.is_a?(Hash) ? label["name"] : label }

        # The repository's labels, read in pages of 100, so a label is never made by adding one that is misspelled.
        def known_labels(repo, token)
          Pages.read(max_pages: 10) do |page|
            listed = Array(GithubApp.get("/repos/#{repo}/labels?per_page=100&page=#{page || 1}", token: token))
            [ listed.map { |label| label["name"] }, (listed.size == 100 ? (page || 1) + 1 : nil) ]
          end.items
        end

        def check_labels!(repo, labels, token)
          return if labels.empty?

          known = known_labels(repo, token)
          unknown = labels.reject { |label| known.any? { |name| name.casecmp?(label) } }
          return if unknown.empty?

          fail! "#{repo} has no #{'label'.pluralize(unknown.size)} #{unknown.to_sentence}, and adding one would make it. " \
                "#{known.any? ? "Its labels are #{known.first(50).join(', ')}." : 'It has no labels.'}"
        end
      end
    end
  end
end
