# A keyed one-way digest of where a setting points, so a service's settings and a store's own addresses can be compared
# without either being kept. The key is the app's secret and the workspace, so the same address reads differently in
# two workspaces and nothing outside Firefight can tell what a digest stands for. workspace is a workspace or its id.
module ResourceMap::Fingerprint
  SALT = "resource_map/fingerprint".freeze

  # A host and port, the host in lower case and without the dot a fully qualified name may end in.
  def self.of(host, port, workspace)
    host = host.to_s.strip.downcase.delete_suffix(".")
    return if host.empty? || port.to_i <= 0

    digest(workspace, "address", "#{host}:#{port.to_i}")
  end

  # The domain a host is one label under, such as pooler.example.com for aws-1-eu.pooler.example.com, with the port,
  # for a provider that names the domain its shared hosts are under rather than each host.
  def self.of_domain(host, port, workspace)
    parent = host.to_s.strip.downcase.delete_suffix(".").split(".", 2).last
    parent&.include?(".") ? of(parent, port, workspace) : nil
  end

  # Something both sides name exactly, such as a secret's ARN a store keeps its password in and a service reads.
  def self.of_reference(reference, workspace)
    reference = reference.to_s.strip
    reference.empty? ? nil : digest(workspace, "reference", reference)
  end

  # A name an address shares with other tenants is told apart by, such as a database's name on a host many share.
  def self.of_name(name, workspace)
    name = name.to_s.strip.downcase
    name.empty? ? nil : digest(workspace, "name", name)
  end

  def self.digest(workspace, kind, text)
    OpenSSL::HMAC.hexdigest("SHA256", key_for(workspace), "#{kind}:#{text}")
  end
  private_class_method :digest

  def self.key_for(workspace)
    base = Rails.application.key_generator.generate_key(SALT, 32)
    OpenSSL::HMAC.digest("SHA256", base, (workspace.respond_to?(:id) ? workspace.id : workspace).to_s)
  end
  private_class_method :key_for
end
