# Inertia returns JSON props (skipping the HTML layout) when X-Inertia headers
# are present. Tests that only verify controller behavior — redirects, session
# state, props — use these to avoid rendering the full layout, which requires
# a built Vite manifest that CI doesn't produce.
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
