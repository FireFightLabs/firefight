import type { ResourceMapLink, ResourceMapResource } from "@/types/serializers"

// One line per setting of a service that names this resource, from the links into it that are facts and carry setting
// names. A suggestion's setting only hints at the store, so it stays with the suggestion's clues.
export interface PointingSetting {
  key: string
  variable: string
  from: ResourceMapResource
}

export function settingsPointingAt(resource: ResourceMapResource, links: ResourceMapLink[], byId: Map<string, ResourceMapResource>): PointingSetting[] {
  return links
    .filter((link) => link.toId === resource.id && !link.unconfirmed)
    .flatMap((link) => {
      const from = byId.get(link.fromId)
      if (!from) {
        return []
      }
      return link.variables.map((variable) => ({ key: `${link.id}:${variable}`, variable, from }))
    })
}
