import { useMemo } from "react"

import type { AbilityActionOption } from "@/types/serializers"

// Grouped under the connection that minted them. Granting an ability and
// choosing what a set covers both need exactly this.
export function useGroupedActions(
  actions: AbilityActionOption[],
  search: string,
  exclude?: Set<string>,
): [string, AbilityActionOption[]][] {
  return useMemo(() => {
    const term = search.toLowerCase()
    const byGroup = new Map<string, AbilityActionOption[]>()

    actions.forEach((action) => {
      if (exclude?.has(action.id)) {
        return
      }
      if (!action.key.toLowerCase().includes(term)) {
        return
      }
      byGroup.set(action.group, [...(byGroup.get(action.group) ?? []), action])
    })

    return [...byGroup.entries()]
  }, [actions, search, exclude])
}
