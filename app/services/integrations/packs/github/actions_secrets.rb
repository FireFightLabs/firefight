module Integrations
  module Packs
    class Github
      # A repository's GitHub Actions secrets, and an environment's (actions/list-repo-secrets, get-repo-public-key,
      # create-or-update-repo-secret and their environment twins in github/rest-api-description). GitHub never answers
      # with a value, so a list is names and dates. Setting one never takes the value as an argument. The person types it
      # in Firefight, or the call names a value Firefight reads itself from another connection (Integrations::
      # SecretHandoffs), and it is sealed with the repository's public key before it leaves, as GitHub asks (Encrypting
      # secrets for the REST API, libsodium sealed box). A repository's secrets are the App's Secrets permission, an
      # environment's its Environments permission.
      module ActionsSecrets
        LIST_SECRETS = "list_actions_secrets".freeze
        SET_SECRET = "set_actions_secret".freeze
        # Letters, digits and underscores, never starting with a digit or GITHUB_ (docs.github.com, Using secrets in GitHub
        # Actions, Naming your secrets).
        SECRET_NAME = /\A(?!GITHUB_)[A-Z_][A-Z0-9_]*\z/i
        ENVIRONMENT_WORDS = "Environments".freeze
        TARGET_REPO = "repo".freeze
        TARGET_NAME = "name".freeze
        TARGET_ENVIRONMENT = "environment".freeze
        SECRETS_LIMIT = 100

        ENVIRONMENT = { "type" => "string", "description" => "A deployment environment of the repository, such as production, for its own secrets (optional, the repository's)" }.freeze

        def self.included(pack)
          pack.tool LIST_SECRETS,
                    description: "The names of a repository's GitHub Actions secrets, or an environment's, with when each was last set. " \
                                 "GitHub never gives a secret's value",
                    params_schema: Code.object_schema({ "repo" => Code::REPO, "environment" => ENVIRONMENT }, %w[repo]),
                    read_only: true

          pack.tool SET_SECRET,
                    description: "Create or replace a GitHub Actions secret in a repository, or in one of its environments. Never pass the " \
                                 "value: the person types it in a secure field Firefight shows under this step, or value_from names a " \
                                 "value Firefight reads itself from another tool, so it never passes through you",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "name" => { "type" => "string", "description" => "The secret's name, such as DEPLOY_HOOK_URL. Letters, digits and underscores" },
                      "environment" => ENVIRONMENT,
                      SecretHandoffs::VALUE_FROM => SecretHandoffs::VALUE_FROM_PARAM
                    }, %w[repo name]),
                    read_only: false
        end

        def list_actions_secrets(environment_row:, arguments:)
          repo = repo_argument(arguments)
          environment = environment_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          secrets_call(LIST_SECRETS, repo, environment) do
            found = GithubApp.get("#{secrets_path(repo, environment)}?per_page=#{SECRETS_LIMIT}", token: token)
            where = environment ? "environment #{environment} of #{repo}" : repo
            secrets = Array(found["secrets"])
            lines = secrets.map { |secret| "  #{secret['name']}  last set #{secret['updated_at'] || secret['created_at']}" }
            more = found["total_count"].to_i > secrets.size ? "\n(#{found['total_count']} in all, the first #{secrets.size} shown)" : ""
            text = secrets.empty? ? "#{where} has no Actions secrets." : "Actions secrets in #{where}:\n#{lines.join("\n")}#{more}"
            linked(text, repo_page(repo, environment ? "settings/environments" : "settings/secrets/actions"))
          end
        end

        # Checks the repository and the permission first, by reading the key the value will be sealed with, so a refusal
        # comes now rather than after the person typed the value.
        def set_actions_secret(environment_row:, arguments:)
          repo = repo_argument(arguments)
          name = secret_name_argument(arguments)
          environment = environment_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          secrets_call(SET_SECRET, repo, environment) { GithubApp.get("#{secrets_path(repo, environment)}/public-key", token: token) }

          where = environment ? "the #{environment} environment of #{repo}" : repo
          target = { TARGET_REPO => repo, TARGET_NAME => name, TARGET_ENVIRONMENT => environment }.compact
          SecretHandoffs.entry_result("#{name} in #{where} waits for its value. #{SecretHandoffs::NOT_IN_A_CHAT}",
                                      target: target, title: "#{name} in #{where}", value_from: arguments[SecretHandoffs::VALUE_FROM],
                                      link: github_link(repo_page(repo, environment ? "settings/environments" : "settings/secrets/actions")))
        end

        # Seals the value with the key GitHub gives for the repository or environment and sends it. Answers what was done.
        def fill_secret(environment_row:, target:, value:)
          repo = target.fetch(TARGET_REPO)
          name = target.fetch(TARGET_NAME)
          environment = target[TARGET_ENVIRONMENT].presence
          token = GithubApp.installation_token(environment_row)
          secrets_call(SET_SECRET, repo, environment) do
            key = GithubApp.get("#{secrets_path(repo, environment)}/public-key", token: token)
            GithubApp.write(:put, "#{secrets_path(repo, environment)}/#{Http.segment(name)}",
                            { "encrypted_value" => ActionsSecrets.sealed(value, key.fetch("key")), "key_id" => key.fetch("key_id") }, token: token)
          end
          "Set #{name} in #{environment ? "the #{environment} environment of #{repo}" : repo}."
        end

        def self.sealed(value, public_key)
          require "rbnacl"
          box = RbNaCl::Boxes::Sealed.from_public_key(RbNaCl::PublicKey.new(Base64.strict_decode64(public_key)))
          Base64.strict_encode64(box.box(value.to_s))
        end

        private

        def secrets_path(repo, environment)
          environment ? "/repos/#{repo}/environments/#{Http.segment(environment)}/secrets" : "/repos/#{repo}/actions/secrets"
        end

        # An environment's secrets need the Environments permission rather than Secrets, which NEEDS cannot say since it
        # depends on the call.
        def secrets_call(tool, repo, environment, &)
          return asking(tool, "GitHub found no repository #{repo}", &) unless environment

          begin
            yield
          rescue GithubApp::NotPermitted => error
            fail! Sentence.join("GitHub refused this", error, after: "Firefight's GitHub App needs #{ENVIRONMENT_WORDS} " \
                                                                     "#{tool == SET_SECRET ? 'read and write' : 'read'} on this installation for an environment's secrets. #{Asking::GRANT_WHERE}")
          rescue GithubApp::NotFound
            fail! Sentence.all("GitHub found no environment #{environment} in #{repo}.", Asking::NOT_GIVEN)
          end
        end

        def secret_name_argument(arguments)
          name = arguments["name"].to_s.strip
          fail!("name must be letters, digits and underscores, not starting with a digit or GITHUB_, such as DEPLOY_HOOK_URL.") unless name.match?(SECRET_NAME)

          name.upcase
        end

        def environment_argument(arguments)
          environment = arguments["environment"].to_s.strip.presence
          fail!("environment is too long.") if environment && environment.length > 255
          environment
        end
      end
    end
  end
end
