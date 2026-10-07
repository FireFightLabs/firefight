# What WorkspaceAdapter.for hands back for a workspace that has not connected a chat platform. Every call raises
# AdapterError::NotConnected, so nothing reads a guessed answer from a platform that is not there. The contract's
# methods are defined, and the high level ones a platform adapter adds beyond it are refused the same way.
class UnconnectedAdapter < PlatformAdapter
  PlatformAdapter.public_instance_methods(false).each do |method_name|
    define_method(method_name) do |*_args, **_options, &_block|
      raise AdapterError::NotConnected
    end
  end

  def method_missing(_method_name, *_args, **_options, &_block)
    raise AdapterError::NotConnected
  end

  # Never claims a method, so conversions such as to_ary are not tried on it.
  def respond_to_missing?(method_name, include_private = false) = super
end
