import type { IncidentPageOwnProps } from "@/pages/incidents/types"

export type IncidentPageProp = keyof IncidentPageOwnProps

// A full visit after a mutation replaces every prop, dropping the deferred timeline and
// actions to skeletons. Naming the props a mutation can change makes the redirect a partial reload.
export function afterMutation(...props: IncidentPageProp[]) {
  return { preserveScroll: true, only: props }
}

// Answering the update form changes the incident and adds to its timeline.
export const UPDATE_VISIT = afterMutation("incident", "timelineEvents")
