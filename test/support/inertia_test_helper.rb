# Inertia returns JSON props (skipping the HTML layout) when X-Inertia headers
# are present. Use these in tests that only check controller behavior, such as
# redirects, session state and props, so the full layout never renders. That
# layout needs a built Vite manifest, which CI does not produce.
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
