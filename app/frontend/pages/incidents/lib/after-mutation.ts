import type { IncidentPageOwnProps } from "@/pages/incidents/types"

export type IncidentPageProp = keyof IncidentPageOwnProps

// Every mutation on the incident page redirects back to it. Left alone, that
// redirect is a full visit: Inertia replaces every prop, the deferred timeline
// and actions arrive absent, and both drop to their skeletons until a second
// request brings them back. Naming the props the mutation can change turns the
// redirect into a partial reload, which merges into what is already on screen
// and leaves the rest untouched. A mutation that redirects to another page is
// unaffected, since the server only honors the list when it renders this page.
export function afterMutation(...props: IncidentPageProp[]) {
  return { preserveScroll: true, only: props }
}
