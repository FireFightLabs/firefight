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
      util-linux procps \
    && rm -rf /var/lib/apt/lists/*

ARG GO_VERSION=1.26.8
RUN arch="$(dpkg --print-architecture)" \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" | tar -C /usr/local -xz

# Language servers, one per language the tools read. The Ruby one runs from its own bundle, so it reads a repository's
# code without installing that repository's gems.
COPY lsp/Gemfile /opt/lsp/ruby/Gemfile
RUN cd /opt/lsp/ruby && bundle lock && bundle install \
    && mkdir -p /opt/tools \
    && npm install --prefix /opt/tools --no-fund --no-audit typescript@5 typescript-language-server pyright \
    && GOBIN=/opt/tools/go/bin GOPATH=/tmp/gopath go install golang.org/x/tools/gopls@latest \
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


COPY server.rb /opt/sandbox/server.rb

EXPOSE 8080
CMD ["ruby", "/opt/sandbox/server.rb"]
