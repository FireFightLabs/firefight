module ProviderDocs
  # An API client on npm whose endpoints are written out as pages. It is installed with its scripts off and loaded by
  # script/provider_docs/api_client_endpoints.mjs under Node's permission model, with no environment, reading only the
  # folder it is installed in and writing only the pages. A version already read is not installed again.
  class Package
    REGISTRY = "https://registry.npmjs.org".freeze
    SCRIPT = Rails.root.join("script/provider_docs/api_client_endpoints.mjs")
    PATHS_FILE = "documented_paths.json".freeze

    def initialize(definition, client:, revisions:, progress:, version: nil)
      @definition = definition
      @client = client
      @revisions = revisions
      @progress = progress
      @version = version
    end

    def read
      package = @definition.address
      released = @client.json("#{REGISTRY}/#{package.sub('/', '%2F')}/latest").fetch("version")
      url = "https://www.npmjs.com/package/#{package}/v/#{released}"
      version = versioned(released)
      if version == @version && @revisions.any?
        @progress.listed(@revisions.size)
        return Reading.new(pages: @revisions.keys.map { |path| Fetched.new(path: path, url: url, content: nil, revision: version) }, listed: @revisions.keys, version: version)
      end

      Dir.mktmpdir do |dir|
        install = File.join(dir, "package")
        out = File.join(dir, "pages")
        FileUtils.mkdir_p([ install, out ])
        run({ "PATH" => ENV.fetch("PATH"), "HOME" => dir, "npm_config_cache" => File.join(dir, "cache") },
            "npm", "install", "--prefix", install, "--ignore-scripts", "--no-save", "--no-package-lock", "--no-audit", "--no-fund", "--silent", "#{package}@#{released}")
        paths = File.join(install, PATHS_FILE)
        File.write(paths, Array(@definition["paths"]).to_json)
        run({ "PATH" => ENV.fetch("PATH") }, "node", "--permission", "--allow-fs-read=#{install}", "--allow-fs-read=#{SCRIPT.dirname}",
            "--allow-fs-write=#{out}", SCRIPT.to_s, install, package, out, @definition.fetch("relative_to"), paths, *Array(@definition["leave_out"]))
        pages = Dir[File.join(out, "**/*.md")].sort.map do |file|
          path = "#{@definition.prefix}#{@definition.fetch('endpoints')}/#{Pathname(file).relative_path_from(out)}"
          Fetched.new(path: path, url: url, content: File.read(file), revision: version)
        end
        raise DocsClient::Error, "#{package} #{released} defines no endpoints" if pages.empty?

        @progress.listed(pages.size)

        license = File.read(File.join(install, "node_modules", package, @definition.fetch("license")))
        Reading.new(pages: pages, listed: pages.map(&:path), version: version, license: license)
      end
    end

    private

    # The client's version, with a digest of the paths written beside its endpoints, so a change to them is read again
    # though the client did not change.
    def versioned(released)
      paths = Array(@definition["paths"])
      paths.empty? ? released : "#{released}+#{Digest::SHA256.hexdigest(paths.to_json).first(8)}"
    end

    def run(env, *command)
      _output, error, status = Open3.capture3(env, *command, unsetenv_others: true)
      raise DocsClient::Error, "#{command.first} failed: #{error.to_s.lines.last(3).join.strip.truncate(300)}" unless status.success?
    end
  end
end
