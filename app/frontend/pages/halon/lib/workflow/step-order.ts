import type { CanvasStep, Edge } from "@/pages/halon/lib/workflow/types"

export interface OrderedStep {
  item: CanvasStep
  // How many for each boxes it sits inside.
  depth: number
}

// The steps in the order they run, for the list a phone shows instead of the canvas: each level in the order its
// connections lead, a step that waits on several after all of them, and the inside of a for each right after it.
// Steps nothing leads to keep the order they were added in.
export function stepsInOrder(items: CanvasStep[], edges: Edge[], within: string | null = null, depth = 0): OrderedStep[] {
  const level = items.filter((item) => (item.step.within ?? null) === within)
  const ids = new Set(level.map((item) => item.step.id))
  const levelEdges = edges.filter((edge) => ids.has(edge.from) && ids.has(edge.to))
  const waiting = new Map(level.map((item) => [ item.step.id, levelEdges.filter((edge) => edge.to === item.step.id).length ]))
  const ready = level.filter((item) => waiting.get(item.step.id) === 0 && !item.suggestion)
  const ordered: CanvasStep[] = []
  while (ready.length > 0) {
    const next = ready.shift()
    if (!next) {
      break
    }
    ordered.push(next)
    for (const edge of levelEdges.filter((each) => each.from === next.step.id)) {
      const left = (waiting.get(edge.to) ?? 0) - 1
      waiting.set(edge.to, left)
      const target = level.find((item) => item.step.id === edge.to)
      if (left === 0 && target) {
        ready.push(target)
      }
    }
  }
  // Steps Halon only suggests, and any a loop of connections leaves out, come last.
  const unplaced = level.filter((item) => !ordered.includes(item))
  return [ ...ordered, ...unplaced ].flatMap((item) => [ { item, depth }, ...stepsInOrder(items, edges, item.step.id, depth + 1) ])
}
