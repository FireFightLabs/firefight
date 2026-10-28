# The subscription proxy (CLIProxyAPI, MIT), unmodified, pinned to one release by digest.
# Changing the version means running the isolation test against it first (script/subscription_proxy_isolation.rb).
FROM eceasy/cli-proxy-api:v8.0.28@sha256:5de1679350c368fb031d46900da30d97c1e9e9a3b150fc4c4181e7e65022a09e

RUN apt-get update \
  && apt-get install -y --no-install-recommends postgresql-client \
  && rm -rf /var/lib/apt/lists/*

COPY config.yaml /CLIProxyAPI/firefight-config.yaml
COPY entrypoint.sh /CLIProxyAPI/firefight-entrypoint.sh
RUN chmod 0755 /CLIProxyAPI/firefight-entrypoint.sh

EXPOSE 8317
ENTRYPOINT ["/CLIProxyAPI/firefight-entrypoint.sh"]
CMD []
