# A source as config/provider_docs.yml writes it. The file says what each kind reads. Its pages are named under to:, so
# two sources of one provider never name the same page.
class ProviderDocSource
  class Definition < Data.define(:key, :provider, :kind, :settings)
    def self.path = Rails.root.join("config/provider_docs.yml")

    KIND_REPOSITORY = "repository".freeze
    KIND_SITE = "site".freeze
    KIND_INDEX = "index".freeze
    KIND_PACKAGE = "package".freeze
    KINDS = {
      KIND_REPOSITORY => %w[paths],
      KIND_SITE => %w[license pages],
      KIND_INDEX => %w[under suffix to],
      KIND_PACKAGE => %w[license endpoints relative_to]
    }.freeze
    OPTIONAL = {
      KIND_REPOSITORY => %w[license notice extensions exclude recursive],
      KIND_SITE => %w[page_url],
      KIND_INDEX => %w[license],
      KIND_PACKAGE => %w[leave_out]
    }.freeze
    SHARED = %w[provider to].freeze
    DEFAULT_PAGE_URL = "%<site>s/%<page>s/index.md".freeze
    GITHUB = %r{\Ahttps://github\.com/(?<repository>[\w.-]+/[\w.-]+)\z}

    def self.all
      @all ||= YAML.safe_load_file(path).map do |key, settings|
        new(key: key, provider: settings.fetch("provider", key), kind: (KINDS.keys & settings.keys).first, settings: settings.freeze)
      end.freeze
    end

    def self.find(key) = all.find { |definition| definition.key == key.to_s }

    def self.of(provider) = all.select { |definition| definition.provider == provider.to_s }

    def [](name) = settings[name.to_s]

    def fetch(name) = settings.fetch(name.to_s)

    def address = settings.fetch(kind)

    # Where its pages are named, such as docs/ for Northflank's product documentation.
    def prefix = settings["to"].present? ? "#{settings['to']}/" : ""

    # The owner/name of a repository source, which GitHub's tree and raw files are read by.
    def repository = address.match(GITHUB)&.[](:repository)

    def page_url(page) = format(settings.fetch("page_url", DEFAULT_PAGE_URL), site: address, page: page)

    # Where its pages are named, each a folder ending in / or one page, so two sources of a provider can be held apart.
    def roots
      case kind
      when KIND_SITE then settings.fetch("pages").keys.map { |path| "#{prefix}#{path}" }
      when KIND_INDEX then [ prefix ]
      when KIND_PACKAGE then [ "#{prefix}#{settings.fetch('endpoints')}/" ]
      when KIND_REPOSITORY then settings.fetch("paths").values.uniq.map { |to| to.end_with?(".md") ? "#{prefix}#{to}" : "#{prefix}#{to}/" }
      end
    end

    # Whether a page path can come from this source, read from this file alone, so a skill naming a guide no source could
    # hold fails a test without reading the web. A folder holds whatever it holds on the day, so any page under it counts.
    def could_hold?(path)
      path = path.to_s
      return false unless path.start_with?(prefix) && path.end_with?(".md") && !path.include?("..")

      inside = path.delete_prefix(prefix)
      case kind
      when KIND_SITE then settings.fetch("pages").key?(inside)
      when KIND_INDEX then true
      when KIND_PACKAGE then inside.start_with?("#{settings.fetch('endpoints')}/")
      when KIND_REPOSITORY
        settings.fetch("paths").values.any? { |to| to.end_with?(".md") ? inside == to : inside.start_with?("#{to}/") && (settings["recursive"] || !inside.delete_prefix("#{to}/").include?("/")) }
      end
    end
  end
end
