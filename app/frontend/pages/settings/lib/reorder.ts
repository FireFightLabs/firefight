import { arrayMove } from "@dnd-kit/sortable"
import type { DragEndEvent } from "@dnd-kit/core"

// Not a hook: builds the onDragEnd handler that submits the new id order.
export function reorderHandler<T extends { id: string }>(
  items: T[],
  submit: (orderedIds: string[]) => void,
) {
  return (event: DragEndEvent) => {
    const { active, over } = event
    if (!over || active.id === over.id) return

    const oldIndex = items.findIndex((item) => item.id === active.id)
    const newIndex = items.findIndex((item) => item.id === over.id)
    if (oldIndex === -1 || newIndex === -1) return

    submit(arrayMove(items, oldIndex, newIndex).map((item) => item.id))
  }
}
