# Firefight's own address, for a link that leaves the app, such as one in a Slack message or a provider's webhook. Read
# from APP_HOST and APP_PROTOCOL, and absent while APP_HOST is unset.
module AppUrl
  # A route helper's host and protocol, or nil.
  def self.options(env = ENV)
    host = env["APP_HOST"].presence
    host && { host: host, protocol: env.fetch("APP_PROTOCOL", "https") }
  end

  # Such as https://firefight.example, or nil.
  def self.root(env = ENV)
    found = options(env)
    found && "#{found[:protocol]}://#{found[:host]}"
  end

  # The path on Firefight's own address, or the path alone while it is not set.
  def self.absolute(path, env = ENV) = "#{root(env)}#{path}"
end
