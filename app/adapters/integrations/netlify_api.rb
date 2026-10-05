module Integrations
  # Calls to Netlify's REST API with a workspace's own personal access token, for the Netlify integration. The paths,
  # parameters and fields are the ones in Netlify's OpenAPI document (netlify/open-api, swagger.yml).
  class NetlifyApi
    class Error < Integrations::Error; end

    API_ROOT = "https://api.netlify.com/api/v1".freeze
    PAGE_SIZE = 100
    MAX_PAGES = 10

    def initialize(token)
      @token = token
    end

    def user = get("/user")

    # Every site the token reaches, a page at a time, as a Pages::Read that says whether any were left unread.
    def sites
      Pages.read(max_pages: MAX_PAGES) do |page|
        page ||= 1
        found = Array(get("/sites", "filter" => "all", "page" => page, "per_page" => PAGE_SIZE))
        [ found, (page + 1 if found.size == PAGE_SIZE) ]
      end
    end

    def site(site_id) = get("/sites/#{Http.segment(site_id)}")

    # production and branch are the swagger's own filters on listSiteDeploys.
    def deploys(site_id, limit:, production: nil, branch: nil)
      query = { "per_page" => limit, "page" => 1, "production" => production, "branch" => branch.presence }
      Array(get("/sites/#{Http.segment(site_id)}/deploys", query))
    end

    def deploy(site_id, deploy_id) = get("/sites/#{Http.segment(site_id)}/deploys/#{Http.segment(deploy_id)}")

    # restoreSiteDeploy publishes an earlier deploy as the live site, without building again.
    def restore(site_id, deploy_id)
      uri = URI.parse("#{API_ROOT}/sites/#{Http.segment(site_id)}/deploys/#{Http.segment(deploy_id)}/restore")
      send_request(uri, Net::HTTP::Post.new(uri))
    end

    private

    def get(path, query = {})
      uri = URI.parse("#{API_ROOT}#{path}")
      pairs = query.compact
      uri.query = URI.encode_www_form(pairs) if pairs.any?
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def send_request(uri, request)
      request["Authorization"] = "Bearer #{@token}"
      Http.json(uri, request, error_class: Error, provider_name: "Netlify")
    end
  end
end
