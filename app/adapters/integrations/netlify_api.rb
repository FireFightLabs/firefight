module Integrations
  # Calls to Netlify's REST API with a workspace's own personal access token, for the Netlify integration. The paths,
  # parameters and fields are the ones in Netlify's OpenAPI document (netlify/open-api, swagger.yml).
  class NetlifyApi
    class Error < Integrations::Error; end
    # Netlify answered that the site or hook is not there, the one answer a re-read takes as gone.
    class NotFound < Error; end
    # Netlify turned the request down as it stands, such as a hook its plan does not allow, as opposed to a token it does
    # not accept.
    class Refused < Error; end
    REFINED = { 400 => Refused, 403 => Refused, 404 => NotFound, 422 => Refused }.freeze

    API_ROOT = "https://api.netlify.com/api/v1".freeze
    PAGE_SIZE = 100
    MAX_PAGES = 10
    # The hook type that posts to an address of one's own.
    URL_HOOK = "url".freeze

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

    # A site's own environment variables (getEnvVars with site_id), each with its values per deploy context. A secret's
    # values are not readable outside Netlify, apart from the local development context's.
    def env_vars(account_id, site_id) = Array(get("/accounts/#{Http.segment(account_id)}/env", "site_id" => site_id))

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

    # The site's outgoing hooks (listHooksBySiteId), each with its type, event, data.url and whether Netlify disabled it,
    # read only to find the ones Firefight made at the connection's own address.
    def hooks(site_id) = Array(get("/hooks", "site_id" => site_id))

    # The hook types the site's plan offers, each with its events and, for this site, the events it restricts (listHookTypes
    # with site_id, as Netlify's own MCP server reads them, netlify/netlify-mcp, events/hooks-api.ts). A hook for a
    # restricted event is stored and never fires.
    def hook_types(site_id) = Array(get("/hooks/types", "site_id" => site_id))

    # An outgoing webhook for one event of one site, signed with secret (createHookBySiteId, a url hook's data is its url
    # and signature_secret, netlify/netlify-mcp, events/hooks-api.ts).
    def create_hook(site_id, event:, url:, secret:)
      write(Net::HTTP::Post, "/hooks", { "type" => URL_HOOK, "event" => event, "data" => { "url" => url, "signature_secret" => secret } }, "site_id" => site_id)
    end

    # Clears a hook Netlify disabled after its deliveries kept failing (enableHook).
    def enable_hook(hook_id) = write(Net::HTTP::Post, "/hooks/#{Http.segment(hook_id)}/enable")

    def delete_hook(hook_id)
      uri = URI.parse("#{API_ROOT}/hooks/#{Http.segment(hook_id)}")
      send_request(uri, Net::HTTP::Delete.new(uri))
    end

    private

    def write(verb, path, body = nil, query = {})
      uri = URI.parse("#{API_ROOT}#{path}")
      uri.query = URI.encode_www_form(query) if query.any?
      request = verb.new(uri)
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      send_request(uri, request)
    end

    def get(path, query = {})
      uri = URI.parse("#{API_ROOT}#{path}")
      pairs = query.compact
      uri.query = URI.encode_www_form(pairs) if pairs.any?
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def send_request(uri, request)
      request["Authorization"] = "Bearer #{@token}"
      Http.json(uri, request, error_class: Error, provider_name: "Netlify", refine: ->(code, _reason) { REFINED[code] })
    end
  end
end
