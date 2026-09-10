const HIGHLIGHT_CLASSES = ["ring-2", "ring-primary/60", "rounded-md"]
const HIGHLIGHT_MS = 1600

export function actionAnchorId(actionId: string) {
  return `action-${actionId}`
}

// Scrolls the sidebar item into view and flashes it, so the reader sees where
// the action is now.
export function revealAction(actionId: string) {
  const element = document.getElementById(actionAnchorId(actionId))
  if (!element) {
    return
  }
  element.scrollIntoView({ behavior: "smooth", block: "center" })
  element.classList.add(...HIGHLIGHT_CLASSES)
  window.setTimeout(() => element.classList.remove(...HIGHLIGHT_CLASSES), HIGHLIGHT_MS)
}
