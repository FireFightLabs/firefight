# syntax=docker/dockerfile:1

# The machine every CI job runs in, so a job starts with Ruby, the gems, Node, the JavaScript packages and Chrome
# already in place instead of installing them. CI tags it with a hash of this file, Gemfile.lock, package-lock.json
# and .ruby-version, and builds it again only when one of them changes.

ARG RUBY_VERSION
ARG NODE_VERSION=22

FROM docker.io/library/node:${NODE_VERSION}-trixie-slim AS node

FROM node AS packages
WORKDIR /opt/ci
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
WORKDIR /opt/ci
COPY Gemfile Gemfile.lock ./
COPY engines/solid_workflow/solid_workflow.gemspec engines/solid_workflow/
COPY engines/solid_workflow/lib/solid_workflow/version.rb engines/solid_workflow/lib/solid_workflow/
COPY engines/firefight_ai/firefight_ai.gemspec engines/firefight_ai/
COPY engines/firefight_ai/lib/firefight_ai/version.rb engines/firefight_ai/lib/firefight_ai/
RUN gem install bundler --no-document -v "$(tail -n 1 Gemfile.lock | tr -d ' ')" && \
    bundle install --jobs "$(nproc)" && \
    rm -rf ~/.bundle "${GEM_HOME}"/cache "${GEM_HOME}"/bundler/gems/*/.git

FROM docker.io/library/ruby:${RUBY_VERSION}-slim

LABEL org.opencontainers.image.source="https://github.com/FireFightLabs/firefight"

# Chrome runs as root here, which it refuses to do inside its sandbox, so chromedriver finds a google-chrome that
# starts it without one. SE_CHROMEDRIVER points Selenium at the driver that matches it, with no download at test time.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates curl git libpq5 libsodium23 libvips libyaml-0-2 postgresql-client \
      ripgrep unzip xz-utils zstd && \
    curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install --no-install-recommends -y /tmp/chrome.deb && \
    major="$(google-chrome --version | sed -E 's/[^0-9]*([0-9]+)\..*/\1/')" && \
    driver="$(curl -fsSL "https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_${major}")" && \
    curl -fsSL -o /tmp/chromedriver.zip "https://storage.googleapis.com/chrome-for-testing-public/${driver}/linux64/chromedriver-linux64.zip" && \
    unzip -j /tmp/chromedriver.zip chromedriver-linux64/chromedriver -d /usr/local/bin && \
    printf '#!/bin/sh\nexec /opt/google/chrome/google-chrome --no-sandbox "$@"\n' > /usr/local/bin/google-chrome && \
    chmod +x /usr/local/bin/google-chrome && \
    ln -sf /usr/local/bin/google-chrome /usr/bin/google-chrome && \
    ln -sf /usr/local/bin/google-chrome /usr/bin/google-chrome-stable && \
    rm -rf /tmp/chrome.deb /tmp/chromedriver.zip /var/lib/apt/lists /var/cache/apt/archives

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY --from=packages /opt/ci/node_modules /opt/ci/node_modules

ENV SE_CHROMEDRIVER=/usr/local/bin/chromedriver
