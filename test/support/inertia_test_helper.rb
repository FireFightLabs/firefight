# With X-Inertia headers the controller returns JSON props and skips the layout, which needs a
# built Vite manifest that CI does not produce.
module InertiaTestHelper
  def inertia_headers
    {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version
    }
  end

  # A partial reload of the named props, deferred ones included, the way a page asks for them once it has shown.
  def inertia_partial_headers(component, props)
    inertia_headers.merge("X-Inertia-Partial-Component" => component, "X-Inertia-Partial-Data" => Array(props).join(","))
  end

  # The open chat as the page holds it once its conversation has loaded.
  def chat_page_headers = inertia_partial_headers("agent/index", AgentChatsController::PROPS.values)

  def inertia_props
    JSON.parse(response.body)["props"]
  end
end
