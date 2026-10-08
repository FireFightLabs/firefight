module ProviderDocs
  # An API client on npm whose endpoints are written out as pages. It is installed with its scripts off and loaded by
  # script/provider_docs/api_client_endpoints.mjs under Node's permission model, with no environment, reading only the
  # folder it is installed in and writing only the pages. A version already read is not installed again.
  class Package
    REGISTRY = "https://registry.npmjs.org".freeze
    SCRIPT = Rails.root.join("script/provider_docs/api_client_endpoints.mjs")

    def initialize(definition, client:, revisions:, version: nil)
      @definition = definition
      @client = client
      @revisions = revisions
      @version = version
    end

    def read
      package = @definition.address
      latest = @client.json("#{REGISTRY}/#{package.sub('/', '%2F')}/latest").fetch("version")
      url = "https://www.npmjs.com/package/#{package}/v/#{latest}"
      if latest == @version && @revisions.any?
        return Reading.new(pages: @revisions.keys.map { |path| Fetched.new(path: path, url: url, content: nil, revision: latest) }, listed: @revisions.keys, version: latest)
      end

      Dir.mktmpdir do |dir|
        install = File.join(dir, "package")
        out = File.join(dir, "pages")
        FileUtils.mkdir_p([ install, out ])
        run({ "PATH" => ENV.fetch("PATH"), "HOME" => dir, "npm_config_cache" => File.join(dir, "cache") },
            "npm", "install", "--prefix", install, "--ignore-scripts", "--no-save", "--no-package-lock", "--no-audit", "--no-fund", "--silent", "#{package}@#{latest}")
        run({ "PATH" => ENV.fetch("PATH") }, "node", "--permission", "--allow-fs-read=#{install}", "--allow-fs-read=#{SCRIPT.dirname}",
            "--allow-fs-write=#{out}", SCRIPT.to_s, install, package, out, @definition.fetch("relative_to"), *Array(@definition["leave_out"]))
        pages = Dir[File.join(out, "**/*.md")].sort.map do |file|
          path = "#{@definition.prefix}#{@definition.fetch('endpoints')}/#{Pathname(file).relative_path_from(out)}"
          Fetched.new(path: path, url: url, content: File.read(file), revision: latest)
        end
        raise DocsClient::Error, "#{package} #{latest} defines no endpoints" if pages.empty?

        license = File.read(File.join(install, "node_modules", package, @definition.fetch("license")))
        Reading.new(pages: pages, listed: pages.map(&:path), version: latest, license: license)
      end
    end

    private

    def run(env, *command)
      _output, error, status = Open3.capture3(env, *command, unsetenv_others: true)
      raise DocsClient::Error, "#{command.first} failed: #{error.to_s.lines.last(3).join.strip.truncate(300)}" unless status.success?
    end
  end
end
