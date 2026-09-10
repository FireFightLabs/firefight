# With X-Inertia headers the controller returns JSON props and skips the layout, which needs a
# built Vite manifest that CI does not produce.
module InertiaTestHelper
  def inertia_headers
    {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version
    }
  end

  def inertia_props
    JSON.parse(response.body)["props"]
  end
end
