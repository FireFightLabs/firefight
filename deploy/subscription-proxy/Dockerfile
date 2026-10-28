# The subscription proxy: CLIProxyAPI (MIT) at one pinned release, built from its own source with one file of
# Firefight's added to its server (firefight_sign_in.go), which stamps every sign-in's credential with the workspace and
# sign-in Firefight started it for. Nothing else in its source changes: the one line where its main collects its server
# options takes Firefight's instead of none, and the build stops if that line is not there.
# Changing the version means moving both pins together and running the isolation test first
# (script/subscription_proxy_isolation.rb).
FROM golang:1.26-bookworm@sha256:23ce71337b726608afb1bc00986e630a05034a87a87ea1fc2cd1ae5cf33387eb AS build

# v8.0.28
ARG CLIPROXYAPI_COMMIT=0d18d3b365be000eeaee7de4615f9da596b2059d
ARG CLIPROXYAPI_VERSION=v8.0.28

WORKDIR /src
RUN git init -q . \
  && git remote add origin https://github.com/router-for-me/CLIProxyAPI.git \
  && git fetch -q --depth 1 origin "$CLIPROXYAPI_COMMIT" \
  && git checkout -q FETCH_HEAD \
  && go mod download

COPY firefight_sign_in.go cmd/server/firefight_sign_in.go
RUN grep -qx '	serverOptions := \[\]api.ServerOption(nil)' cmd/server/main.go \
  && sed -i 's/^\tserverOptions := \[\]api.ServerOption(nil)$/\tserverOptions := firefightServerOptions()/' cmd/server/main.go \
  && grep -qx '	serverOptions := firefightServerOptions()' cmd/server/main.go \
  && CGO_ENABLED=1 GOOS=linux go build -buildvcs=false \
       -ldflags="-s -w -X 'main.Version=${CLIPROXYAPI_VERSION}-firefight' -X 'main.Commit=${CLIPROXYAPI_COMMIT}'" \
       -o /out/CLIProxyAPI ./cmd/server/

# The release's own image, for everything around the binary.
FROM eceasy/cli-proxy-api:v8.0.28@sha256:5de1679350c368fb031d46900da30d97c1e9e9a3b150fc4c4181e7e65022a09e

# psql, pinned. Debian drops a version once a newer one ships, and the build then stops here until both are moved.
ARG POSTGRESQL_CLIENT_VERSION=15+248+deb12u1
ARG POSTGRESQL_CLIENT_15_VERSION=15.19-0+deb12u1
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       "postgresql-client=${POSTGRESQL_CLIENT_VERSION}" "postgresql-client-15=${POSTGRESQL_CLIENT_15_VERSION}" \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/CLIProxyAPI /CLIProxyAPI/CLIProxyAPI
COPY config.yaml /CLIProxyAPI/firefight-config.yaml
COPY entrypoint.sh /CLIProxyAPI/firefight-entrypoint.sh
RUN chmod 0755 /CLIProxyAPI/firefight-entrypoint.sh

EXPOSE 8317
ENTRYPOINT ["/CLIProxyAPI/firefight-entrypoint.sh"]
CMD []
