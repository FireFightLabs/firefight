import { router } from "@inertiajs/react"
import { useCallback, useState } from "react"

import { WORKFLOW_RUN_QUERY_PARAM, WORKFLOW_VERSION_QUERY_PARAM, WORKFLOW_VIEW_QUERY_PARAM } from "@/lib/generated/constants"
import { replaceQuery } from "@/lib/query"
import { workflowPath } from "@/lib/routes"
import { type CanvasView, VIEWS } from "@/pages/halon/lib/workflow/types"

function viewFromUrl(): CanvasView {
  const asked = new URLSearchParams(window.location.search).get(WORKFLOW_VIEW_QUERY_PARAM)
  return Object.values(VIEWS).find((view) => view === asked) ?? VIEWS.EDITOR
}

// Which view the canvas shows, and which version or run, all in the address, so a link opens the same place. Opening a
// version or a run is a visit of its own, since the server draws it.
export function useCanvasView(workflowId: string) {
  const [ view, setView ] = useState<CanvasView>(viewFromUrl)

  const show = useCallback((next: CanvasView) => {
    setView(next)
    replaceQuery({ [WORKFLOW_VIEW_QUERY_PARAM]: next === VIEWS.EDITOR ? null : next })
  }, [])

  const openVersion = useCallback((versionId: string) => {
    setView(VIEWS.EDITOR)
    router.get(workflowPath(workflowId, { [WORKFLOW_VERSION_QUERY_PARAM]: versionId }))
  }, [ workflowId ])

  const openRun = useCallback((runId: string) => {
    setView(VIEWS.EDITOR)
    router.get(workflowPath(workflowId, { [WORKFLOW_RUN_QUERY_PARAM]: runId }))
  }, [ workflowId ])

  const leave = useCallback(() => {
    setView(VIEWS.EDITOR)
    router.get(workflowPath(workflowId))
  }, [ workflowId ])

  return { view, show, openVersion, openRun, leave }
}
