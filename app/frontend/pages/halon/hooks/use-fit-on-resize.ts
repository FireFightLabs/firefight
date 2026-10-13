import { type FitViewOptions, useReactFlow } from "@xyflow/react"
import { type RefObject, useEffect } from "react"

// The canvas fits the workflow again when its own width changes, such as Halon's panel opening beside it, so no step
// is left behind the panels. A change in height alone, such as a banner coming and going, leaves the view as it is.
export function useFitOnResize(container: RefObject<HTMLElement | null>, options: FitViewOptions) {
  const { fitView } = useReactFlow()

  useEffect(() => {
    const element = container.current
    if (!element) {
      return
    }

    let width = element.clientWidth
    const observer = new ResizeObserver(() => {
      if (element.clientWidth === width) {
        return
      }
      width = element.clientWidth
      void fitView(options)
    })
    observer.observe(element)
    return () => observer.disconnect()
  }, [ container, fitView, options ])
}
