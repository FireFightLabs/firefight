# The box Halon reads code in. Commands arrive over HTTP from the app and run as an unprivileged user,
# so nothing a repository contains can change the service or the copies other commands read.
FROM ruby:3.4-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    MISE_DATA_DIR=/opt/mise \
    MISE_CONFIG_DIR=/opt/mise/config \
    MISE_CACHE_DIR=/opt/mise/cache \
    PATH=/opt/mise/shims:/usr/local/bundle/bin:/usr/local/go/bin:/opt/tools/node_modules/.bin:/opt/tools/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git ripgrep universal-ctags \
      build-essential pkg-config libpq-dev libyaml-dev libssl-dev zlib1g-dev libffi-dev \
      nodejs npm python3 python3-pip python3-venv \
      postgresql redis-server \
      libvips42 fonts-dejavu-core \
      util-linux procps shellcheck \
      dnsutils jq sqlite3 xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Debian's Postgres carries the contrib extensions (pg_trgm, hstore, uuid-ossp, citext, pgcrypto and the rest) but not
# pgvector, so it is built from a pinned release, portable across CPUs. What building it installed is removed by name,
# since apt's autoremove keeps the compilers another package suggests.
ARG PGVECTOR_VERSION=v0.8.6
RUN pg="$(ls /usr/lib/postgresql)" \
    && dpkg-query -W -f '${Package}\n' | sort > /tmp/before \
    && apt-get update && apt-get install -y --no-install-recommends "postgresql-server-dev-${pg}" \
    && git clone --quiet --depth 1 --branch "${PGVECTOR_VERSION}" https://github.com/pgvector/pgvector.git /tmp/pgvector \
    && make -C /tmp/pgvector OPTFLAGS="" with_llvm=no \
    && make -C /tmp/pgvector with_llvm=no install \
    && dpkg-query -W -f '${Package}\n' | sort > /tmp/after \
    && apt-get purge -y $(comm -13 /tmp/before /tmp/after) \
    && rm -rf /tmp/pgvector /tmp/before /tmp/after /var/lib/apt/lists/*

ARG GO_VERSION=1.26.8
RUN arch="$(dpkg --print-architecture)" \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" | tar -C /usr/local -xz

# Language servers, one per language the tools read, and OpenCode, the coding agent a code fix runs, reaching its model
# only through Firefight. The Ruby one runs from its own bundle, so it reads a repository's
# code without installing that repository's gems. actionlint and shellcheck check a code fix's CI workflows and scripts
# before its pull request opens.
COPY lsp/Gemfile /opt/lsp/ruby/Gemfile
RUN cd /opt/lsp/ruby && bundle lock && bundle install \
    && mkdir -p /opt/tools \
    && npm install --prefix /opt/tools --no-fund --no-audit typescript@5 typescript-language-server pyright opencode-ai@1.18.34 \
    && GOBIN=/opt/tools/go/bin GOPATH=/tmp/gopath go install golang.org/x/tools/gopls@latest \
    && GOBIN=/opt/tools/go/bin GOPATH=/tmp/gopath go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 \
    && rm -rf /tmp/gopath /root/.npm

# reader reads the code and cannot write it. runner runs a repository's tests in a copy of its own.
RUN useradd --create-home --shell /bin/sh reader \
    && useradd --create-home --shell /bin/sh runner \
    && git config --system safe.directory '*' \
    && git config --system core.hooksPath /dev/null \
    && mkdir -p /code /work /runs \
    && chown runner:runner /runs

# A repository's own tool versions (.ruby-version, .nvmrc, mise.toml) are installed on demand before its tests run, by runner.
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh \
    && mkdir -p /opt/mise/config /opt/mise/cache /opt/mise/installs /opt/mise/shims \
    && chown -R runner:runner /opt/mise


# Halon's terminal. halon writes only its own folder, so nothing it runs touches a repository or a test copy. Provider
# command line tools reach their APIs through Firefight with the command's own token, never a key. Northflank's needs a
# newer Node than Debian's, so it runs on a pinned one of its own.
ARG NODE_FOR_CLIS_VERSION=22.20.0
ARG NORTHFLANK_CLI_VERSION=0.13.0
RUN useradd --create-home --shell /bin/bash halon \
    && mkdir -p /terminal/results && chown -R halon:halon /terminal \
    && arch="$(dpkg --print-architecture | sed 's/amd64/x64/')" \
    && mkdir -p /opt/clis/node \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_FOR_CLIS_VERSION}/node-v${NODE_FOR_CLIS_VERSION}-linux-${arch}.tar.xz" | tar -C /opt/clis/node --strip-components=1 -xJ \
    && PATH=/opt/clis/node/bin:$PATH npm install --prefix /opt/clis --no-fund --no-audit "@northflank/cli@${NORTHFLANK_CLI_VERSION}" \
    && printf '#!/bin/sh\nexec /opt/clis/node/bin/node /opt/clis/node_modules/@northflank/cli/dist/cli.js "$@"\n' > /usr/local/bin/northflank \
    && chmod 755 /usr/local/bin/northflank \
    && rm -rf /root/.npm

# kubectl reads its server and token only from flags or a kubeconfig, so a wrapper hands it the ones the box was given.
ARG KUBECTL_VERSION=v1.34.1
RUN arch="$(dpkg --print-architecture)" \
    && curl -fsSL -o /opt/clis/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl" \
    && chmod 755 /opt/clis/kubectl

COPY bin/ff /usr/local/bin/ff
COPY bin/kubectl /usr/local/bin/kubectl
COPY outside_check.rb /opt/sandbox/outside_check.rb
COPY server.rb /opt/sandbox/server.rb

EXPOSE 8080
CMD ["ruby", "/opt/sandbox/server.rb"]
