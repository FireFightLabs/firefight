import { BaseEdge, EdgeLabelRenderer, type EdgeProps, getSmoothStepPath } from "@xyflow/react"
import { IconX } from "@tabler/icons-react"
import type { MouseEvent } from "react"

import { cn } from "@/lib/utils"
import { WORKFLOW_EDIT_OPERATIONS, WORKFLOW_ROUTE_ERROR } from "@/lib/generated/constants"
import { SuggestionDecision } from "@/pages/halon/components/workflow/suggestion-decision"
import { useCanvasActions } from "@/pages/halon/hooks/use-canvas-actions"
import type { RouteFlowEdge } from "@/pages/halon/lib/workflow/canvas-graph"
import { routeWords } from "@/pages/halon/lib/workflow/labels"

const CORNER_RADIUS = 10
// A route's name sits on the last stretch into the step it leads to, clear of where routes part.
const ROUTE_LABEL_RISE = 18

// A connection between two steps, drawn as a line with rounded elbows and labelled with its route when it has one. A
// connection Halon suggests adding is dashed in violet, and one it suggests taking away is struck. A selected
// connection can be taken away with its own button.
export function RouteEdge({ id, source, target, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, data, selected, markerEnd }: EdgeProps<RouteFlowEdge>) {
  const { disconnect } = useCanvasActions()
  const [ path, middleX, middleY ] = getSmoothStepPath({ sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, borderRadius: CORNER_RADIUS })
  const suggestion = data?.suggestion ?? null
  const adding = suggestion?.operation === WORKFLOW_EDIT_OPERATIONS.CONNECT
  const removing = suggestion?.operation === WORKFLOW_EDIT_OPERATIONS.DISCONNECT
  const error = data?.route === WORKFLOW_ROUTE_ERROR
  const stroke = suggestion || data?.halonMarked ? "var(--halon)" : error ? "var(--danger)" : selected || data?.lit ? "var(--lime)" : "var(--border-control)"

  function remove(event: MouseEvent) {
    event.stopPropagation()
    if (data) {
      disconnect({ from: source, to: target, route: data.route, within: data.within })
    }
  }

  return (
    <>
      <BaseEdge
        id={id}
        path={path}
        markerEnd={markerEnd}
        style={{
          stroke,
          strokeWidth: selected ? 1.75 : 1.25,
          strokeDasharray: adding ? "4 4" : removing ? "2 5" : data?.implied ? "3 4" : undefined,
          opacity: removing ? 0.6 : data?.implied ? 0.55 : 1,
        }}
      />
      {(data?.route || suggestion || (selected && !data?.readOnly)) && (
        <EdgeLabelRenderer>
          {data?.route && (
            <span
              className={cn(
                "nodrag nopan pointer-events-none absolute -translate-x-1/2 -translate-y-1/2 rounded-full border bg-background px-2 py-0.5 font-mono text-[10.5px] text-fg-muted",
                error ? "border-error-border text-error" : "border-border-strong",
                removing && "line-through decoration-halon",
              )}
              style={{ left: targetX, top: targetY - ROUTE_LABEL_RISE }}
            >
              {routeWords(data.route)}
            </span>
          )}
          <div
            className="nodrag nopan pointer-events-auto absolute flex -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-1.5"
            style={{ left: middleX, top: middleY }}
          >
            {suggestion && (
              <div className="rounded-md border border-halon-border bg-background p-1.5">
                <p className="mb-1.5 max-w-48 text-[11px] leading-snug text-halon">{suggestion.words}</p>
                <SuggestionDecision suggestion={suggestion} acceptLabel={adding ? "Connect" : "Disconnect"} />
              </div>
            )}
            {selected && !suggestion && !data?.readOnly && (
              <button
                type="button"
                aria-label="Remove this connection"
                className="flex size-6 items-center justify-center rounded-full border border-border-strong bg-background text-fg-muted hover:border-error-border hover:text-error"
                onClick={remove}
              >
                <IconX className="size-3.5" />
              </button>
            )}
          </div>
        </EdgeLabelRenderer>
      )}
    </>
  )
}
