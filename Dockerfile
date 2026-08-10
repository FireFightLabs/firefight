# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t firefight .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name firefight firefight

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.5
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages including Node.js for Vite
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates curl libjemalloc2 libvips postgresql-client nodejs npm && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock vendor ./
COPY engines/solid_workflow engines/solid_workflow
COPY engines/firefight_ai engines/firefight_ai

# Off for self-host/GHCR; the cloud build sets these to install the private
# firefight_cloud gem (git_token authenticates the clone of the private repo).
ARG FIREFIGHT_CLOUD=""
ARG FIREFIGHT_CLOUD_REF=""

RUN --mount=type=secret,id=git_token \
    if [ -n "$FIREFIGHT_CLOUD" ]; then \
      export FIREFIGHT_CLOUD=1 FIREFIGHT_CLOUD_REF="$FIREFIGHT_CLOUD_REF" BUNDLE_DEPLOYMENT=0; \
      TOKEN="$(cat /run/secrets/git_token 2>/dev/null || true)"; \
      [ -n "$TOKEN" ] && git config --global url."https://x-access-token:${TOKEN}@github.com/".insteadOf "https://github.com/"; \
    fi; \
    bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# COPY above restored the committed Gemfile.lock, which intentionally excludes
# firefight_cloud. Re-resolve for the cloud build so the in-image lock matches
# the Gemfile and the frozen bundler commands below succeed.
RUN --mount=type=secret,id=git_token \
    if [ -n "$FIREFIGHT_CLOUD" ]; then \
      export FIREFIGHT_CLOUD=1 FIREFIGHT_CLOUD_REF="$FIREFIGHT_CLOUD_REF" BUNDLE_DEPLOYMENT=0; \
      TOKEN="$(cat /run/secrets/git_token 2>/dev/null || true)"; \
      [ -n "$TOKEN" ] && git config --global url."https://x-access-token:${TOKEN}@github.com/".insteadOf "https://github.com/"; \
      bundle install && \
      rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git; \
    fi

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Install Node.js and build frontend assets
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y nodejs npm && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install frontend dependencies
RUN npm install

# Pages contributed by the cloud engine live inside that gem, and the host
# directory Vite globs is gitignored, so it is empty in the build context.
# Without this the bundle ships without them and the routes render blank.
RUN if [ -n "$FIREFIGHT_CLOUD" ]; then \
      export FIREFIGHT_CLOUD=1; \
      bundle exec rake firefight_cloud:sync_frontend; \
    fi

# Build Vite assets
RUN bundle exec vite build

# Final stage for app image
FROM base

# Bake the cloud flag into the runtime so the Gemfile matches the lock baked at
# build time: set on cloud images, empty on self-host images.
ARG FIREFIGHT_CLOUD=""
ENV FIREFIGHT_CLOUD=${FIREFIGHT_CLOUD}

# Stamp the deployed version onto every OpenTelemetry span (service.version).
# Northflank passes this build arg from the git ref/commit of the build;
# defaults to "dev" for local/manual builds without it.
ARG SERVICE_VERSION="dev"
ENV OTEL_SERVICE_VERSION=${SERVICE_VERSION}

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
