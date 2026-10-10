module Integrations
  module ReadGuards
    # api_read only ever sends a GET to the cluster's API server, under /api and /apis, so what the guard settles is which
    # GETs read and which answer secrets. The proxy subresources (of a pod, a service or a node) pass a GET on to whatever
    # runs there, which may change something, and exec, attach and portforward open a session inside a container, so none
    # is a read (Kubernetes API reference, Pod v1 and Node v1, proxy operations, and kubectl's exec, attach and
    # port-forward). A Secret's data and stringData are its values, so Secrets are read as names. Every other field
    # holding a token is hidden wherever it sits (ApiReads::SECRET_FIELDS).
    module Kubernetes
      extend PathReads

      INSIDE = "Reaches inside what runs in the cluster, which a read never does. Read the object itself, or its logs with " \
               "workload_logs.".freeze
      REFUSED = {
        %r{\A(?!/(api|apis)(/|\z)|/version\z)} => "Kubernetes reads are paths under /api or /apis, such as /api/v1/namespaces/default/pods.",
        %r{/proxy(/|\z)} => INSIDE,
        %r{/(exec|attach|portforward)\z} => INSIDE
      }.freeze
      SECRET_PATHS = %r{/secrets(/|\z)}
    end
  end
end
