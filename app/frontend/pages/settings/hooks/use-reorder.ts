import { arrayMove } from "@dnd-kit/sortable"
import type { DragEndEvent } from "@dnd-kit/core"

// Sends the new order as soon as a row is dropped, and renders whatever the
// server sends back. No local copy of the order, so the list on screen is
// always the list on the server.
export function useReorder<T extends { id: string }>(
  items: T[],
  submit: (orderedIds: string[]) => void,
) {
  function onDragEnd(event: DragEndEvent) {
    const { active, over } = event
    if (!over || active.id === over.id) return

    const oldIndex = items.findIndex((item) => item.id === active.id)
    const newIndex = items.findIndex((item) => item.id === over.id)
    if (oldIndex === -1 || newIndex === -1) return

    submit(arrayMove(items, oldIndex, newIndex).map((item) => item.id))
  }

  return { onDragEnd }
}
