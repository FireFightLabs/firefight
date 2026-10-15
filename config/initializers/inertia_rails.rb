# frozen_string_literal: true

InertiaRails.configure do |config|
  config.version = ViteRuby.digest
  config.encrypt_history = true
  config.always_include_errors_hash = true
  config.use_script_element_for_initial_page = true
  config.use_data_inertia_head_attribute = true
end

# A scroll prop's metadata given as a lambda is read only when the prop is sent, so a partial reload that names other
# props never pages through a list it does not return. It answers the same keys as a hash.
class LazyScrollMetadata
  def match?(metadata) = metadata.is_a?(Proc)

  def call(metadata, **options) = InertiaRails::ScrollMetadata::HashAdapter.new.call(metadata.call, **options)
end

InertiaRails::ScrollMetadata.register_adapter(LazyScrollMetadata)
