const HIGHLIGHT_CLASSES = ["ring-2", "ring-primary/60", "rounded-md"]
const HIGHLIGHT_MS = 1600

export function actionAnchorId(actionId: string) {
  return `action-${actionId}`
}

// A timeline entry about an action item points at the item in the sidebar:
// scroll it into view and flash it, so the reader can see where it is now.
export function revealAction(actionId: string) {
  const element = document.getElementById(actionAnchorId(actionId))
  if (!element) {
    return
  }
  element.scrollIntoView({ behavior: "smooth", block: "center" })
  element.classList.add(...HIGHLIGHT_CLASSES)
  window.setTimeout(() => element.classList.remove(...HIGHLIGHT_CLASSES), HIGHLIGHT_MS)
}
