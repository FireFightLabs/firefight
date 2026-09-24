# The command service inside a sandbox. The app pushes repositories in and asks for commands by argument list,
# never by a string the box would have to trust. Standard library only, so the image carries nothing to keep patched.
require "socket"
require "json"
require "open3"
require "fileutils"
require "tmpdir"
require "securerandom"
require "digest"
require "uri"

module Sandbox
  KEY = ENV.fetch("SANDBOX_KEY")
  PORT = Integer(ENV.fetch("PORT", "8080"))
  CODE = "/code"
  WORK = "/work"
  RUNS = "/runs"
  OUTPUT_LIMIT = 10 * 1024 * 1024
  DEFAULT_TIMEOUT = 60
  MAX_TIMEOUT = 20 * 60
  USERS = %w[reader runner].freeze
  REPO_NAME = /\A[\w.\-]+__[\w.\-]+\z/
  LOCKS = Hash.new { |hash, key| hash[key] = Mutex.new }
  LOCKS_GUARD = Mutex.new

  # The image's own settings every command needs, such as where the base image keeps its gems. Nothing else is passed on.
  INHERITED = %w[PATH GEM_HOME BUNDLE_APP_CONFIG BUNDLE_SILENCE_ROOT_WARNING MISE_DATA_DIR MISE_CONFIG_DIR MISE_CACHE_DIR].freeze

  class Refused < StandardError; end

  def self.base_env(home) = ENV.to_h.slice(*INHERITED).merge("HOME" => home, "LANG" => "C.UTF-8", "GIT_TERMINAL_PROMPT" => "0")

  def self.lock(key, &)
    mutex = LOCKS_GUARD.synchronize { LOCKS[key] }
    mutex.synchronize(&)
  end

  # Runs argv with no shell, as the given user when one is named, and gives up after timeout seconds.
  def self.run(argv, dir: "/", user: nil, timeout: DEFAULT_TIMEOUT, env: {}, stdin: nil)
    command = user ? [ "setpriv", "--reuid=#{user}", "--regid=#{user}", "--init-groups", "--", *argv ] : argv
    base = base_env(user ? "/home/#{user}" : "/root")
    out = +""
    err = +""
    truncated = false
    timed_out = false
    status = nil
    Open3.popen3(base.merge(env), *command, chdir: dir, pgroup: true, unsetenv_others: true) do |input, stdout, stderr, waiter|
      input.write(stdin) if stdin
      input.close
      readers = [ [ stdout, out ], [ stderr, err ] ].map do |stream, buffer|
        Thread.new do
          while (chunk = stream.readpartial(64 * 1024) rescue nil)
            if buffer.bytesize + chunk.bytesize > OUTPUT_LIMIT
              buffer << chunk.byteslice(0, OUTPUT_LIMIT - buffer.bytesize)
              truncated = true
            else
              buffer << chunk
            end
          end
        end
      end
      unless waiter.join(timeout)
        timed_out = true
        Process.kill("KILL", -waiter.pid) rescue nil
      end
      status = waiter.value
      readers.each { |reader| reader.join(5) }
    end
    {
      "stdout" => out.force_encoding(Encoding::UTF_8).scrub, "stderr" => err.force_encoding(Encoding::UTF_8).scrub,
      "exit_code" => status&.exitstatus, "timed_out" => timed_out, "truncated" => truncated
    }
  end

  def self.run!(argv, **options)
    result = run(argv, **options)
    raise Refused, "#{argv.first} failed: #{result['stderr'].strip.lines.last(3).join}" unless result["exit_code"] == 0

    result["stdout"]
  end

  module Repos
    def self.bare(name)
      raise Refused, "Not a repository name: #{name}" unless name.to_s.match?(REPO_NAME)

      File.join(CODE, "#{name}.git")
    end

    # A second push of the same repository fetches into it, so a box keeps one copy with every commit it was sent.
    def self.push(name, bundle)
      path = bare(name)
      Sandbox.lock("repo:#{name}") do
        Dir.mktmpdir do |tmp|
          file = File.join(tmp, "repo.bundle")
          File.binwrite(file, bundle)
          if File.directory?(path)
            Sandbox.run!([ "git", "--git-dir", path, "fetch", "--quiet", "--force", file, "+refs/*:refs/*" ])
          else
            Sandbox.run!([ "git", "clone", "--quiet", "--bare", file, path ])
          end
        end
        head = Sandbox.run!([ "git", "--git-dir", path, "rev-parse", "HEAD" ]).strip
        branch = Sandbox.run!([ "git", "--git-dir", path, "symbolic-ref", "--short", "HEAD" ]).strip
        { "head" => head, "default_branch" => branch }
      end
    end

    def self.commit(name, ref)
      wanted = ref.to_s.strip.empty? ? "HEAD" : ref.to_s
      raise Refused, "Not a ref: #{wanted}" if wanted.start_with?("-")

      result = Sandbox.run([ "git", "--git-dir", bare(name), "rev-parse", "--verify", "--quiet", "#{wanted}^{commit}" ])
      raise Refused, "#{name} has no commit #{wanted}" unless result["exit_code"] == 0

      result["stdout"].strip
    end

    # A read-only checkout per commit, shared by every read at that commit.
    def self.checkout(name, sha)
      dir = File.join(WORK, name, sha)
      Sandbox.lock("checkout:#{dir}") do
        unless File.directory?(dir)
          FileUtils.mkdir_p(File.dirname(dir))
          Sandbox.run!([ "git", "--git-dir", bare(name), "worktree", "add", "--quiet", "--detach", dir, sha ])
        end
      end
      dir
    end

    # A writable copy for runner, kept for the life of the box so dependencies install once.
    def self.run_copy(name, sha)
      dir = File.join(RUNS, "#{name}-#{sha}")
      Sandbox.lock("run:#{dir}") do
        unless File.directory?(dir)
          Sandbox.run!([ "git", "clone", "--quiet", "--no-checkout", bare(name), dir ], user: "runner")
          Sandbox.run!([ "git", "checkout", "--quiet", "--detach", sha ], dir: dir, user: "runner")
        end
      end
      dir
    end
  end

  module Services
    STARTED = {}

    def self.start(names)
      Array(names).each_with_object({}) do |name, env|
        case name
        when "postgres" then env.merge!(postgres)
        when "redis" then env.merge!(redis)
        else raise Refused, "No service called #{name}. There are postgres and redis."
        end
      end
    end

    def self.postgres
      Sandbox.lock("service:postgres") do
        unless STARTED["postgres"]
          data = "/var/lib/postgresql/sandbox"
          bin = Dir["/usr/lib/postgresql/*/bin"].max
          unless File.directory?(data)
            FileUtils.mkdir_p(data)
            FileUtils.chown("postgres", "postgres", data)
            Sandbox.run!([ "#{bin}/initdb", "-D", data, "-A", "trust", "-U", "runner" ], user: "postgres")
          end
          Sandbox.run!([ "#{bin}/pg_ctl", "-D", data, "-l", "/tmp/postgres.log", "-o", "-k /tmp -c listen_addresses=127.0.0.1", "-w", "start" ], user: "postgres")
          STARTED["postgres"] = true
        end
      end
      { "DATABASE_URL" => "postgres://runner@127.0.0.1:5432/postgres", "PGHOST" => "127.0.0.1", "PGUSER" => "runner" }
    end

    def self.redis
      Sandbox.lock("service:redis") do
        unless STARTED["redis"]
          Sandbox.run!([ "redis-server", "--daemonize", "yes", "--bind", "127.0.0.1", "--save", "", "--appendonly", "no" ], user: "runner")
          STARTED["redis"] = true
        end
      end
      { "REDIS_URL" => "redis://127.0.0.1:6379/0" }
    end
  end

  # Installs what a repository's lockfiles and version files ask for, once per copy.
  module Prepare
    STEPS = [
      [ ".tool-versions", [ "mise", "install", "--yes" ] ],
      [ "mise.toml", [ "mise", "install", "--yes" ] ],
      [ ".ruby-version", [ "mise", "install", "--yes" ] ],
      [ ".nvmrc", [ "mise", "install", "--yes" ] ],
      [ "Gemfile.lock", [ "sh", "-c", "bundle config set --local path vendor/bundle && bundle install --jobs 4" ] ],
      [ "package-lock.json", [ "npm", "ci", "--no-fund", "--no-audit" ] ],
      [ "yarn.lock", [ "sh", "-c", "corepack enable --install-directory ~/.local/bin && yarn install --frozen-lockfile" ] ],
      [ "pnpm-lock.yaml", [ "sh", "-c", "corepack enable --install-directory ~/.local/bin && pnpm install --frozen-lockfile" ] ],
      [ "requirements.txt", [ "sh", "-c", "python3 -m venv .venv && .venv/bin/pip install -r requirements.txt" ] ],
      [ "go.mod", [ "go", "mod", "download" ] ]
    ].freeze

    # The versions a repository asks for, through mise's shims, for everything that runs in its copy.
    def self.env(dir) = { "MISE_YES" => "1", "MISE_TRUSTED_CONFIG_PATHS" => dir, "MISE_IDIOMATIC_VERSION_FILE_ENABLE_TOOLS" => "ruby,node,python,go" }

    def self.run(dir)
      marker = File.join(dir, ".sandbox-prepared")
      return { "prepared" => [], "already" => true } if File.exist?(marker)

      done = []
      env = self.env(dir)
      STEPS.each do |file, argv|
        next unless File.exist?(File.join(dir, file))
        next if argv.first == "mise" && done.any? { |step| step["command"].start_with?("mise") }

        result = Sandbox.run(argv, dir: dir, user: "runner", timeout: MAX_TIMEOUT, env: env)
        done << { "file" => file, "command" => argv.join(" "), "exit_code" => result["exit_code"],
                  "output" => (result["stdout"] + result["stderr"]).lines.last(40).join }
      end
      FileUtils.touch(marker) if done.all? { |step| step["exit_code"] == 0 }
      { "prepared" => done, "already" => false }
    end
  end

  # One language server per checkout and language, kept alive so the second question is fast.
  class LanguageServer
    COMMANDS = {
      "ruby" => [ "ruby-lsp" ],
      "typescript" => [ "typescript-language-server", "--stdio" ],
      "javascript" => [ "typescript-language-server", "--stdio" ],
      "go" => [ "gopls" ],
      "python" => [ "pyright-langserver", "--stdio" ]
    }.freeze
    EXTENSIONS = {
      "ruby" => %w[.rb .rake], "typescript" => %w[.ts .tsx], "javascript" => %w[.js .jsx .mjs .cjs],
      "go" => %w[.go], "python" => %w[.py]
    }.freeze
    # The Ruby server reads the repository's files but loads only its own gems, never the repository's.
    ENVIRONMENTS = { "ruby" => { "BUNDLE_GEMFILE" => "/opt/lsp/ruby/Gemfile" } }.freeze
    TSSERVER = { "tsserver" => { "path" => "/opt/tools/node_modules/typescript/lib/tsserver.js" } }.freeze
    INITIALIZATION = { "typescript" => TSSERVER, "javascript" => TSSERVER }.freeze
    INSTANCES = {}
    REPLY_TIMEOUT = 60
    # These index the whole repository after starting and answer nothing useful until they say they are done.
    INDEXING = %w[ruby go].freeze
    INDEX_TIMEOUT = 180

    def self.for(dir, language)
      raise Refused, "No language server for #{language}. There are #{COMMANDS.keys.join(', ')}." unless COMMANDS.key?(language)

      Sandbox.lock("lsp:#{dir}:#{language}") { INSTANCES["#{dir}:#{language}"] ||= new(dir, language) }
    end

    def self.language_of(path)
      EXTENSIONS.find { |_language, extensions| extensions.include?(File.extname(path)) }&.first
    end

    def initialize(dir, language)
      @dir = dir
      @language = language
      @next_id = 0
      @opened = {}
      @mutex = Mutex.new
      argv = [ "setpriv", "--reuid=runner", "--regid=runner", "--init-groups", "--", *COMMANDS.fetch(language) ]
      env = Sandbox.base_env("/home/runner").merge(ENVIRONMENTS.fetch(language, {}))
      @input, @output, @errors, @waiter = Open3.popen3(env, *argv, chdir: dir, unsetenv_others: true)
      Thread.new { @errors.each_line { } rescue nil }
      request("initialize", {
        "processId" => Process.pid, "rootUri" => uri(dir), "capabilities" => { "window" => { "workDoneProgress" => true } },
        "workspaceFolders" => [ { "uri" => uri(dir), "name" => File.basename(dir) } ], "initializationOptions" => INITIALIZATION.fetch(language, {})
      })
      notify("initialized", {})
      wait_for_index if INDEXING.include?(language)
    end

    def ask(method, path, line: nil, column: nil, query: nil)
      @mutex.synchronize do
        if method == "workspace/symbol"
          # Some servers only search the project of a file that is open, so a file naming it is opened first.
          file = file_mentioning(query.to_s)
          open_file(file) if file
          return request("workspace/symbol", { "query" => query.to_s })
        end

        open_file(path)
        params = { "textDocument" => { "uri" => uri(File.join(@dir, path)) }, "position" => { "line" => line.to_i - 1, "character" => column.to_i - 1 } }
        params["context"] = { "includeDeclaration" => true } if method == "textDocument/references"
        request(method, params)
      end
    end

    private

    def file_mentioning(text)
      patterns = EXTENSIONS.fetch(@language).map { |extension| "*#{extension}" }
      found = Sandbox.run([ "rg", "--files-with-matches", "--fixed-strings", "--max-count=1", *patterns.flat_map { |pattern| [ "--glob", pattern ] }, "--", text, "." ],
                          dir: @dir, user: "runner", timeout: 30)
      found["stdout"].lines.map { |line| line.chomp.delete_prefix("./") }.min_by(&:length)
    end

    def open_file(path)
      return if @opened[path]

      full = File.join(@dir, path)
      raise Refused, "No file #{path}" unless File.file?(full)

      notify("textDocument/didOpen", { "textDocument" => { "uri" => uri(full), "languageId" => @language, "version" => 1, "text" => File.read(full) } })
      @opened[path] = true
    end

    def uri(path) = "file://#{URI::DEFAULT_PARSER.escape(path)}"

    def notify(method, params) = write({ "jsonrpc" => "2.0", "method" => method, "params" => params })

    def request(method, params)
      id = (@next_id += 1)
      write({ "jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params })
      message = pump(REPLY_TIMEOUT) { |incoming| incoming["id"] == id && !incoming.key?("method") }
      raise Refused, "The #{@language} language server did not answer #{method} in #{REPLY_TIMEOUT} seconds" unless message
      raise Refused, "#{method}: #{message.dig('error', 'message')}" if message["error"]

      message["result"]
    end

    # A server that never reports progress is asked anyway once the time is up, which is no worse than not waiting.
    def wait_for_index
      pump(INDEX_TIMEOUT) { |incoming| incoming["method"] == "$/progress" && incoming.dig("params", "value", "kind") == "end" }
    end

    # Reads until a message matches or the time is up. A server asking us something, such as its configuration, is
    # answered with nothing so it carries on.
    def pump(seconds)
      deadline = Time.now + seconds
      loop do
        remaining = deadline - Time.now
        return nil if remaining <= 0
        return nil unless IO.select([ @output ], nil, nil, remaining)

        message = read
        write({ "jsonrpc" => "2.0", "id" => message["id"], "result" => nil }) if message["method"] && message.key?("id")
        return message if yield(message)
      end
    end

    def write(message)
      body = JSON.generate(message)
      @input.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}")
      @input.flush
    end

    def read
      length = nil
      while (header = @output.gets("\r\n"))
        break if header == "\r\n"

        length = header.split(":", 2).last.to_i if header.downcase.start_with?("content-length")
      end
      raise Refused, "The #{@language} language server stopped" if length.nil?

      JSON.parse(@output.read(length))
    end
  end

  module Handler
    def self.call(method, path, body)
      case [ method, path ]
      in [ "GET", "/health" ] then { "ok" => true }
      in [ "PUT", %r{\A/repos/([^/]+)\z} ] then Repos.push(Regexp.last_match(1), body)
      in [ "POST", "/exec" ] then exec(JSON.parse(body))
      in [ "POST", "/prepare" ] then prepare(JSON.parse(body))
      in [ "POST", "/lsp" ] then lsp(JSON.parse(body))
      else raise Refused, "No route #{method} #{path}"
      end
    end

    # where is "git" for a command that reads the repository's objects, "checkout" for one that reads files at a
    # commit, and "run" for one that runs in runner's writable copy.
    def self.exec(request)
      name = request.fetch("repo")
      sha = Repos.commit(name, request["ref"])
      argv = Array(request.fetch("argv")).map(&:to_s)
      raise Refused, "An empty command" if argv.empty?

      timeout = request.fetch("timeout", DEFAULT_TIMEOUT).to_i.clamp(1, MAX_TIMEOUT)
      case request.fetch("where", "checkout")
      when "git"
        argv = argv.map { |part| part == "{commit}" ? sha : part }
        Sandbox.run([ "git", "--git-dir", Repos.bare(name), *argv ], user: "reader", timeout: timeout).merge("commit" => sha)
      when "checkout"
        Sandbox.run(argv, dir: Repos.checkout(name, sha), user: "reader", timeout: timeout).merge("commit" => sha)
      when "run"
        dir = Repos.run_copy(name, sha)
        env = Services.start(request["services"]).merge(Prepare.env(dir))
        Sandbox.run([ "mise", "exec", "--", *argv ], dir: dir, user: "runner", timeout: timeout, env: env).merge("commit" => sha)
      else raise Refused, "No place called #{request['where']}"
      end
    end

    def self.prepare(request)
      name = request.fetch("repo")
      sha = Repos.commit(name, request["ref"])
      Prepare.run(Repos.run_copy(name, sha)).merge("commit" => sha)
    end

    def self.lsp(request)
      name = request.fetch("repo")
      sha = Repos.commit(name, request["ref"])
      dir = Repos.run_copy(name, sha)
      language = request["language"] || LanguageServer.language_of(request["path"].to_s)
      raise Refused, "Say which language to ask about" unless language

      result = LanguageServer.for(dir, language).ask(
        request.fetch("method"), request["path"].to_s, line: request["line"], column: request["column"], query: request["query"]
      )
      { "result" => result, "root" => dir, "commit" => sha }
    end
  end

  module Http
    MAX_BODY = 1024 * 1024 * 1024

    def self.serve
      server = TCPServer.new("0.0.0.0", PORT)
      $stdout.puts("sandbox listening on #{PORT}")
      loop { Thread.new(server.accept) { |socket| handle(socket) } }
    end

    def self.handle(socket)
      request_line = socket.gets("\r\n").to_s
      method, target = request_line.split(" ", 3)
      headers = {}
      while (line = socket.gets("\r\n")) && line != "\r\n"
        key, value = line.split(":", 2)
        headers[key.strip.downcase] = value.to_s.strip
      end
      return respond(socket, 401, { "error" => "Wrong key" }) unless authorized?(headers["authorization"])

      length = headers["content-length"].to_i
      return respond(socket, 413, { "error" => "Too large" }) if length > MAX_BODY

      body = length.positive? ? socket.read(length) : ""
      respond(socket, 200, Handler.call(method, target.to_s.split("?").first, body))
    rescue Refused, KeyError, JSON::ParserError => error
      respond(socket, 422, { "error" => error.message })
    rescue StandardError => error
      respond(socket, 500, { "error" => "#{error.class}: #{error.message}" })
    ensure
      socket.close unless socket.closed?
    end

    def self.authorized?(header)
      given = header.to_s.delete_prefix("Bearer ")
      given.bytesize == KEY.bytesize && Digest::SHA256.digest(given) == Digest::SHA256.digest(KEY)
    end

    def self.respond(socket, status, payload)
      body = JSON.generate(payload)
      socket.write("HTTP/1.1 #{status} #{status == 200 ? 'OK' : 'Error'}\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
    end
  end
end

Sandbox::Http.serve if $PROGRAM_NAME == __FILE__
