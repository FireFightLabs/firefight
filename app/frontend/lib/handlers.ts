// Radix reports both directions through onOpenChange, but most dialogs only
// care about the close. This keeps that if out of the markup.
export function whenClosed(handler: () => void) {
  return (open: boolean) => {
    if (!open) {
      handler()
    }
  }
}

export function whenOpened(handler: () => void) {
  return (open: boolean) => {
    if (open) {
      handler()
    }
  }
}
