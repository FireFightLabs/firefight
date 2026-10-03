import { useState } from "react"

const STORAGE_KEY = "firefight.agent.chatListCollapsed"

// Remembered per browser. Storage can be refused, in a private window for one, and then the list stays open.
function readCollapsed(): boolean {
  try {
    return window.localStorage.getItem(STORAGE_KEY) === "true"
  } catch {
    return false
  }
}

function writeCollapsed(collapsed: boolean) {
  try {
    window.localStorage.setItem(STORAGE_KEY, String(collapsed))
  } catch {
    // Not remembered, the list still follows the click.
  }
}

export function useChatListCollapsed() {
  const [ collapsed, setCollapsed ] = useState(readCollapsed)

  function collapse() {
    setCollapsed(true)
    writeCollapsed(true)
  }

  function expand() {
    setCollapsed(false)
    writeCollapsed(false)
  }

  return { collapsed, collapse, expand }
}
