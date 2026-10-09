// Sets each key, or removes it when null, without a visit. The state passes through
// because Inertia keeps its page there, and a null state breaks Back to this page.
export function replaceQuery(changes: Record<string, string | null>) {
  const params = new URLSearchParams(window.location.search)
  Object.entries(changes).forEach(([key, value]) => {
    if (value) {
      params.set(key, value)
    } else {
      params.delete(key)
    }
  })
  const query = params.toString()
  window.history.replaceState(window.history.state, "", query ? `${window.location.pathname}?${query}` : window.location.pathname)
}
