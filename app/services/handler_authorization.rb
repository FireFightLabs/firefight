# Mirrors Mcp::Tools::Base.authorize_as. An undeclared handler raises rather
# than silently inheriting a default.
module HandlerAuthorization
  NONE = :none

  def authorize_as(resource, action = Ability::Action::ACTION_READ)
    @authorization = [ resource, action ]
  end

  def authorizes_nothing
    @authorization = NONE
  end

  def authorization
    @authorization || raise(NotImplementedError, "#{name} declares no authorization")
  end
end
