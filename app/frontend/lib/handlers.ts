/**
 * Radix reports both directions through `onOpenChange`, but most dialogs and
 * sheets only care about the close. Wrapping it here keeps that `if` out of
 * the markup, so the JSX reads as a declaration rather than a branch.
 *
 *   <Dialog open={open} onOpenChange={whenClosed(onDismiss)}>
 */
export function whenClosed(handler: () => void) {
  return (open: boolean) => {
    if (!open) {
      handler()
    }
  }
}
