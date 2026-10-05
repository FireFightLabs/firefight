module Integrations
  module Capabilities
    # What the uptime tools share (OpenStatus, Better Stack, Honeybadger's uptime checks): which of the addresses they
    # check is on one of a resource's hostnames.
    module Monitors
      module_function

      # The monitors whose address is on one of the resource's hostnames. Each is a hash with its address under url.
      def watching(resource, monitors)
        names = resource.served_hostnames
        monitors.select { |monitor| names.include?(host_of(monitor["url"])) }
      end

      # A host on its own, from a URL or a bare host, lower case, or nil.
      def host_of(address)
        text = address.to_s.strip
        return if text.empty?

        URI.parse(text.include?("://") ? text : "https://#{text}").host&.downcase&.delete_suffix(".")
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
