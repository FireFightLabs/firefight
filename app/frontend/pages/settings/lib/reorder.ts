import { useState } from "react"
import { arrayMove } from "@dnd-kit/sortable"
import type { DragEndEvent } from "@dnd-kit/core"

// Shows the dropped order straight away and keeps showing it until the server
// confirms it, so rows never jump back while the request is in flight. The
// override is dropped only when the server's order matches it, which keeps a
// second drag from flashing back to the result of the first.
export function useOptimisticOrder<T extends { id: string }>(items: T[]) {
  const [orderIds, setOrderIds] = useState<string[] | null>(null)

  const serverIds = items.map((item) => item.id)
  const stale = orderIds !== null && (
    orderIds.join() === serverIds.join() ||
    orderIds.length !== items.length ||
    orderIds.some((id) => !serverIds.includes(id))
  )
  if (stale) {
    setOrderIds(null)
  }

  const byId = new Map(items.map((item) => [ item.id, item ]))
  const ordered = orderIds && !stale
    ? orderIds.map((id) => byId.get(id)!)
    : items

  function onDragEnd(event: DragEndEvent, submit: (orderedIds: string[], onFailure: () => void) => void) {
    const { active, over } = event
    if (!over || active.id === over.id) {
      return
    }

    const oldIndex = ordered.findIndex((item) => item.id === active.id)
    const newIndex = ordered.findIndex((item) => item.id === over.id)
    if (oldIndex === -1 || newIndex === -1) {
      return
    }

    const nextIds = arrayMove(ordered, oldIndex, newIndex).map((item) => item.id)
    setOrderIds(nextIds)
    submit(nextIds, () => setOrderIds(null))
  }

  return { ordered, onDragEnd }
}
