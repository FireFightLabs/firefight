import { useEffect, useRef, useState } from "react"
import { arrayMove } from "@dnd-kit/sortable"
import type { DragEndEvent } from "@dnd-kit/core"

const REORDER_DELAY_MS = 600

// Keeps the dragged order on screen straight away and sends one request once
// the dragging settles. Without this, rearranging five rows fires five requests
// and five toasts, and each server round trip fights the next drag.
export function useDebouncedReorder<T extends { id: string }>(
  items: T[],
  submit: (orderedIds: string[]) => void,
) {
  const [order, setOrder] = useState(items)
  const pending = useRef<ReturnType<typeof setTimeout> | null>(null)
  const submitRef = useRef(submit)
  submitRef.current = submit

  // Adopt the server's order whenever it actually differs, which covers both
  // our own settled reorder and any other visit that reloads the page props.
  const serverKey = items.map((item) => item.id).join()
  const lastServerKey = useRef(serverKey)
  if (serverKey !== lastServerKey.current) {
    lastServerKey.current = serverKey
    if (!pending.current) setOrder(items)
  }

  // Keep non-order changes (a rename, a toggle) visible during the debounce.
  const itemsById = new Map(items.map((item) => [ item.id, item ]))
  const resolved = order.map((item) => itemsById.get(item.id) ?? item).filter((item) => itemsById.has(item.id))

  useEffect(() => {
    return () => {
      if (pending.current) clearTimeout(pending.current)
    }
  }, [])

  function onDragEnd(event: DragEndEvent) {
    const { active, over } = event
    if (!over || active.id === over.id) return

    const oldIndex = resolved.findIndex((item) => item.id === active.id)
    const newIndex = resolved.findIndex((item) => item.id === over.id)
    if (oldIndex === -1 || newIndex === -1) return

    const next = arrayMove(resolved, oldIndex, newIndex)
    setOrder(next)

    if (pending.current) clearTimeout(pending.current)
    pending.current = setTimeout(() => {
      pending.current = null
      submitRef.current(next.map((item) => item.id))
    }, REORDER_DELAY_MS)
  }

  return { items: resolved, onDragEnd }
}
