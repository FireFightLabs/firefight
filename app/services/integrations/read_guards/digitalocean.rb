module Integrations
  module ReadGuards
    # api_read only ever sends a GET to DigitalOcean's API (digitalocean/openapi, DigitalOcean-public.v2.yaml), so what
    # the guard settles is which GETs answer secrets. A Kubernetes cluster's kubeconfig and credentials
    # (kubernetes_get_kubeconfig, kubernetes_get_credentials) and the registry's Docker credentials
    # (registry_get_dockerCredentials) are nothing but credentials. An app's logs answer signed addresses that read the
    # logs for anyone who has them (apps_get_logs, historic_urls and live_url), so app_logs reads them instead. A database
    # cluster's users and connection pools answer passwords, Spaces keys their secret, a Functions namespace the key that
    # calls it, and an agent's API keys their values, so they are read as names.
    module Digitalocean
      extend PathReads

      REFUSED = {
        %r{\A/v2/kubernetes/clusters/[^/]+/(kubeconfig|credentials)\z} =>
          "A Kubernetes cluster's kubeconfig and credentials are its keys, so a read never fetches them. Its nodes, pools and " \
          "status are read under the cluster itself.",
        %r{\A/v2/registry/docker-credentials\z} =>
          "The registry's Docker credentials are a key to push and pull, so a read never fetches them.",
        %r{\A/v2/apps/[^/]+/(deployments/[^/]+/)?(components/[^/]+/)?logs\z} =>
          "An app's logs come back as signed addresses that read them for anyone who has them, so the general read never " \
          "fetches them. Read them with app_logs, which keeps the addresses to itself."
      }.freeze
      SECRET_PATHS = %r{\A/v2/databases/[^/]+/(users|pools)|\A/v2/spaces/keys|\A/v2/functions/namespaces|/api_keys(/|\z)}
    end
  end
end
