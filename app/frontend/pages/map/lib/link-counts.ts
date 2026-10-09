import type { ResourceMapLink } from "@/types/serializers"

export interface LinkCount {
  facts: number
  suggested: number
}

export function linkCounts(links: ResourceMapLink[]): Map<string, LinkCount> {
  const counts = new Map<string, LinkCount>()
  for (const link of links) {
    for (const id of [ link.fromId, link.toId ]) {
      const count = counts.get(id) ?? { facts: 0, suggested: 0 }
      if (link.unconfirmed) {
        count.suggested += 1
      } else {
        count.facts += 1
      }
      counts.set(id, count)
    }
  }
  return counts
}
