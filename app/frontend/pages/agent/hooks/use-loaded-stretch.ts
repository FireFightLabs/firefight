import { router } from "@inertiajs/react"
import { useEffect, useRef } from "react"

import { AGENT_CHAT_LOADED_FROM_HEADER } from "@/lib/generated/constants"
import { agentChatPath } from "@/lib/routes"

interface Stretch {
  conversationId: string | null
  oldestShown: string | null
}

// Every visit to the open chat, and every change made from it, names the oldest message on screen, so what it reads
// again covers all the person scrolled back through rather than only the newest page. A visit to another chat names none,
// so reading one ahead and opening it ask for the same thing.
export function useLoadedStretch(conversationId: string | null, oldestShown: string | null) {
  const stretch = useRef<Stretch>({ conversationId, oldestShown })

  useEffect(() => {
    stretch.current = { conversationId, oldestShown }
  }, [ conversationId, oldestShown ])

  useEffect(() => {
    return router.on("before", (event) => {
      const { conversationId: open, oldestShown: oldest } = stretch.current
      const visit = event.detail.visit
      if (!open || !oldest || (visit.method === "get" && visit.url.pathname !== agentChatPath(open))) {
        return
      }

      visit.headers = { ...visit.headers, [AGENT_CHAT_LOADED_FROM_HEADER]: oldest }
    })
  }, [])
}
