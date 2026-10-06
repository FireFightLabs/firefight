# Where a store says it can be reached, such as the host and port a provider documents for a database, kept as a keyed
# digest (ResourceMap::Fingerprint) to compare with what services' settings name. A host many tenants share, such as a
# regional proxy, also names what tells its tenants apart, the database's name or the suffix on the user's name.
class ResourceMap::Endpoint < ApplicationRecord
  self.table_name = "resource_map_endpoints"

  Found = Data.define(:resource, :fingerprint, :within_domain, :port, :database_fingerprint, :tenant_fingerprint) do
    def initialize(resource:, fingerprint:, port:, within_domain: false, database_fingerprint: nil, tenant_fingerprint: nil) = super
  end

  belongs_to :workspace
  belongs_to :resource, class_name: "ResourceMap::Resource"
  belongs_to :integration_environment

  # The address resource (a Found's key) is reached at, or nil for a host or port that is missing. The host is only
  # digested here and never kept.
  def self.at(resource:, host:, port:, workspace:, database: nil, tenant: nil)
    fingerprint = ResourceMap::Fingerprint.of(host, port, workspace)
    return unless fingerprint

    Found.new(resource: resource, fingerprint: fingerprint, port: port.to_i,
              database_fingerprint: ResourceMap::Fingerprint.of_name(database, workspace),
              tenant_fingerprint: ResourceMap::Fingerprint.of_name(tenant, workspace))
  end

  # Any host one label under domain, for a provider whose shared hosts cannot be named one by one, such as a pooler
  # numbered per cluster. Only a tenant or a database tells a store's own connections apart there, so one is required.
  def self.within(resource:, domain:, port:, workspace:, database: nil, tenant: nil)
    return if database.blank? && tenant.blank?

    found = at(resource: resource, host: domain, port: port, workspace: workspace, database: database, tenant: tenant)
    found&.with(within_domain: true)
  end

  # Something a service's setting names exactly, such as the ARN of the secret the store keeps its password in.
  def self.reference(resource:, reference:, workspace:)
    fingerprint = ResourceMap::Fingerprint.of_reference(reference, workspace)
    fingerprint && Found.new(resource: resource, fingerprint: fingerprint, port: 0)
  end
end
