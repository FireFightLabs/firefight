class CommandParser
  def self.parse(_payload)
    raise NotImplementedError, "#{name} must implement .parse"
  end
end
