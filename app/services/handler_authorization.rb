# The [resource, crud action] pair the Ability Gateway authorizes a Slack
# command or interaction as. Mirrors Mcp::Tools::Base.authorize_as so both
# entry points declare authorization the same way, and an undeclared handler
# raises rather than silently inheriting a default.
module HandlerAuthorization
  # Handlers that touch nothing: dialog dismissal, no-ops, unknown routes.
  NONE = :none

  def authorize_as(resource, action = ApiKey::ACTION_READ)
    @authorization = [ resource, action ]
  end

  def authorizes_nothing
    @authorization = NONE
  end

  def authorization
    @authorization || raise(NotImplementedError, "#{name} declares no authorization")
  end
end
