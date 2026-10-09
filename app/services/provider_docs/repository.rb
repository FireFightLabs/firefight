module ProviderDocs
  # A GitHub repository, read through its tree, which names every file with the hash of its content, so a file whose
  # hash did not change is not read again. One request lists the tree, and each changed file is read raw.
  class Repository
    API = "https://api.github.com/repos".freeze
    RAW = "https://raw.githubusercontent.com".freeze
    REF = "HEAD".freeze

    def initialize(definition, client:, revisions:, progress:)
      @definition = definition
      @client = client
      @revisions = revisions
      @progress = progress
    end

    def read
      repository = @definition.repository or raise DocsClient::Error, "#{@definition.address} is not a GitHub repository"
      tree = @client.json("#{API}/#{repository}/git/trees/#{REF}?recursive=1", headers: { "X-GitHub-Api-Version" => "2022-11-28" })
      raise DocsClient::Error, "GitHub listed only part of #{repository}" if tree["truncated"]

      blobs = tree.fetch("tree").select { |entry| entry["type"] == "blob" }.to_h { |entry| [ entry["path"], entry["sha"] ] }
      Pages.read(pages_in(blobs), client: @client, revisions: @revisions, license: license(blobs), progress: @progress,
                                  version: "#{REF} tree #{tree['sha'].to_s.first(12)}") do |path, from|
        sha = blobs.fetch(from)
        content = @client.file(raw(from)).body unless @revisions[path] == sha
        Fetched.new(path: path, url: page_url(from), content: content, revision: sha)
      end
    end

    private

    # Each page the source names, by the path it is kept at, to the file it is read from.
    def pages_in(blobs)
      left_out = Array(@definition["exclude"])
      extensions = Array(@definition["extensions"] || [ "md" ])
      @definition.fetch("paths").each_with_object({}) do |(from, to), found|
        if blobs.key?(from)
          found["#{@definition.prefix}#{to}"] = from
          next
        end
        inside = blobs.keys.select { |path| path.start_with?("#{from}/") && extensions.include?(File.extname(path).delete_prefix(".")) } - left_out
        inside = inside.reject { |path| path.delete_prefix("#{from}/").include?("/") } unless @definition["recursive"]
        raise DocsClient::Error, "#{@definition.address} has no #{from}" if inside.empty?

        inside.each { |path| found["#{@definition.prefix}#{to}/#{path.delete_prefix("#{from}/").sub(/\.[a-z]+\z/, '.md')}"] = path }
      end
    end

    def license(blobs)
      texts = [ @definition["license"], @definition["notice"] ].compact.select { |path| blobs.key?(path) }.map { |path| @client.file(raw(path)).body }
      texts.join("\n\n").presence
    end

    def raw(path) = "#{RAW}/#{@definition.repository}/#{REF}/#{escaped(path)}"

    def page_url(path) = "https://github.com/#{@definition.repository}/blob/#{REF}/#{escaped(path)}"

    def escaped(path) = path.split("/").map { |segment| ERB::Util.url_encode(segment) }.join("/")
  end
end
