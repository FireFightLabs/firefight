module Integrations
  # A repository's setup read from its own CI through the code host that holds it, and kept as its RepositorySetup. A
  # code host's pack answers ci_setup(environment_row, repository:) with a Found, or raises Missing in its own words when
  # the repository has no CI it can read. Only a host's own files know its CI's format, and what every format shares
  # is here: which command runs the tests, a service named by its image, and variables a sandbox can use.
  module CiSetup
    class Missing < Integrations::Error; end

    # services are RepositorySetup::Service hashes, env the variables, commands what runs before the tests, source where
    # they were read (a file and its job) and notes what was left out and why, as sentences.
    Found = Data.define(:services, :env, :commands, :source, :notes) do
      def initialize(notes: [], **) = super
    end

    # A command that runs a repository's tests, which is what run_tests or the coding agent runs, so it is not setup.
    TEST_COMMAND = /\b(test|tests|spec|specs|rspec|pytest|jest|vitest|mocha|phpunit|ctest|tox|nox)\b/i
    # Images named differently from the service the sandbox starts.
    IMAGE_NAMES = { "postgresql" => "postgres" }.freeze
    LOCALHOST = "127.0.0.1".freeze
    # A variable such as DB_HOST, REDIS_HOSTNAME or ELASTIC_ADDR.
    HOST_VARIABLE = /(HOST|HOSTNAME|ADDR|ADDRESS|SERVER)\z/i

    module_function

    def reads?(integration)
      pack = NativePack.for(integration.provider)
      pack.present? && pack.method_defined?(:ci_setup)
    end

    def read(environment_row, repository)
      NativePack.fetch!(environment_row.integration).ci_setup(environment_row, repository: repository)
    end

    # The repository's setup in this connection, read from its CI and kept the first time it is asked for. nil when the
    # host reads no CI, the repository has none or it could not be read, so preparing goes ahead without one.
    def for(environment_row, repository)
      integration = environment_row.integration
      RepositorySetup.for(integration, repository) || (derive!(environment_row, repository) if reads?(integration))
    rescue Integrations::Error => error
      Rails.logger.info({ event: "ci_setup.unread", integration_id: integration&.id, repository: repository.to_s, error: error.message }.to_json)
      nil
    end

    # Reads the setup from the repository's CI again and keeps it, replacing what was kept, edits included. Raises
    # Missing or the host's error when it could not.
    def derive!(environment_row, repository)
      found = read(environment_row, repository)
      integration = environment_row.integration
      setup = RepositorySetup.find_or_initialize_by(integration: integration, repository: repository.to_s) { |row| row.workspace = integration.workspace }
      setup.derived!(services: found.services, env: found.env, commands: found.commands, source: found.source, notes: found.notes)
      setup
    rescue ActiveRecord::RecordNotUnique
      RepositorySetup.for(environment_row.integration, repository)
    end

    # The service a CI image runs, such as postgres for postgres:16-alpine or bitnami/postgresql, or fallback.
    def service_name(image, fallback = nil)
      base = image.to_s.split("@").first.to_s.split("/").last.to_s.split(":").first.to_s.downcase
      name = IMAGE_NAMES.fetch(base, base).presence || fallback.to_s.downcase
      name.presence
    end

    # The setup commands and the test command among a job's commands: the last one that runs tests, or the last one when
    # none says so, with what came after it left out too.
    def split(commands)
      index = commands.rindex { |command| command.match?(TEST_COMMAND) } || (commands.size - 1)
      [ commands.first([ index, 0 ].max), commands[index], commands.drop(index + 1) ]
    end

    # Variables a sandbox can use. A value the CI system fills in itself (expression? says which) is left out, a service
    # the job reached by name (hosts) is reached on the box itself, a URL's password is taken out since the sandbox's
    # services take any, and a value that looks like a credential is left out. Answers the variables and the notes.
    def usable_env(env, expression:, hosts: [])
      filled, kept = env.to_h.partition { |_name, value| expression.call(value.to_s) }.map(&:to_h)
      kept = kept.to_h { |name, value| [ name, local(name.to_s, value.to_s, hosts) ] }
      unpassworded = kept.select { |_name, value| value.match?(Chat::SecretFree::CREDENTIAL_URL) }.keys
      kept = kept.transform_values { |value| value.gsub(%r{(\b[a-z][a-z0-9+.-]*://[^\s:@/]+):[^\s@/]+@}i, '\1@') }
      secret = kept.select { |_name, value| Chat::SecretFree::SECRET_PATTERNS.values.any? { |pattern| value.match?(pattern) } }.keys
      notes = []
      notes << "Left out #{filled.keys.to_sentence}, which the CI system fills in itself." if filled.any?
      notes << "Took the password out of #{unpassworded.to_sentence}, since the sandbox's services take any password." if unpassworded.any?
      notes << "Left out #{secret.to_sentence}, which looks like a credential." if secret.any?
      [ kept.except(*secret), notes ]
    end

    # A value naming a service by the host its job reached it at, naming it on the box instead: the host of a URL, or
    # the whole value of a variable whose name says it holds a host.
    def local(name, value, hosts)
      hosts.reduce(value) do |kept, host|
        next LOCALHOST if kept == host && name.match?(HOST_VARIABLE)

        kept.gsub(%r{(://(?:[^@/\s]*@)?)#{Regexp.escape(host)}(?=[:/?]|\z)}) { "#{Regexp.last_match(1)}#{LOCALHOST}" }
      end
    end

    # one_shell says the job runs its commands one after another in one shell, so a cd or an export carries on, and
    # the setup is kept that way, stopping at the first that fails.
    def found(services:, env:, commands:, source:, expression:, hosts: [], notes: [], one_shell: false)
      setup, test, after = split(commands)
      setup = [ "set -e\n#{setup.join("\n")}" ] if one_shell && setup.any?
      kept, env_notes = usable_env(env, expression: expression, hosts: hosts)
      services = services.map { |service| service.merge("env" => usable_env(service["env"].to_h, expression: expression, hosts: hosts).first) }
      said = notes.dup
      said << "Left out the command that runs the tests (#{test.lines.first.strip}), since Halon runs the tests it needs itself." if test
      said << steps_left_out(after.size, "after the tests")
      Found.new(services: services, env: kept, commands: setup, source: source, notes: (said + env_notes).compact)
    end

    def steps_left_out(count, words) = count.positive? ? "Left out #{count} #{'step'.pluralize(count)} #{words}." : nil

    # A CI file read as data, or nil with why it could not be.
    def yaml(text)
      [ YAML.safe_load(text.to_s, permitted_classes: [ Date, Time ], aliases: true), nil ]
    rescue Psych::Exception => error
      [ nil, error.message.lines.first.to_s.strip ]
    end
  end
end
