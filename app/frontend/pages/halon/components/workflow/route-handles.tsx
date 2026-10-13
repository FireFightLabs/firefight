import { Handle, Position } from "@xyflow/react"

import { cn } from "@/lib/utils"
import { WORKFLOW_ROUTE_ERROR } from "@/lib/generated/constants"
import { OUT_HANDLE } from "@/pages/halon/lib/workflow/canvas-graph"
import { routeWords } from "@/pages/halon/lib/workflow/labels"

const HANDLE = "!size-2 !min-h-0 !min-w-0 !rounded-full !border !border-border-control !bg-surface-card"

// Where a connection leaves a step: one way out, or one way out for each route the step can take, so a connection drawn
// from yes carries on only when it took yes. A route nothing leaves on yet carries its name, and one already connected
// is named on its connection. The error route leaves in the danger colour.
export function RouteHandles({ routes, connected, connectable }: { routes: string[]; connected: string[]; connectable: boolean }) {
  const own = routes.filter((route) => route !== WORKFLOW_ROUTE_ERROR)
  const error = routes.includes(WORKFLOW_ROUTE_ERROR)

  if (own.length === 0) {
    return (
      <>
        <Handle id={OUT_HANDLE} type="source" position={Position.Bottom} className={HANDLE} isConnectable={connectable} />
        {error && (
          <Handle
            id={WORKFLOW_ROUTE_ERROR}
            type="source"
            position={Position.Right}
            className={cn(HANDLE, "!border-error-border")}
            isConnectable={connectable}
            title={routeWords(WORKFLOW_ROUTE_ERROR)}
          />
        )}
      </>
    )
  }

  return (
    <div className="absolute inset-x-2 -bottom-3 flex justify-center gap-1.5">
      {own.map((route) => (
        <span
          key={route}
          className={cn(
            "relative rounded-full border border-border-strong bg-background font-mono text-[10px] text-fg-muted",
            connected.includes(route) ? "size-2.5 p-0" : "px-1.5 py-px",
          )}
          title={routeWords(route)}
        >
          {connected.includes(route) ? null : routeWords(route)}
          <Handle id={route} type="source" position={Position.Bottom} className={cn(HANDLE, "!-bottom-1")} isConnectable={connectable} />
        </span>
      ))}
      {error && (
        <span
          className={cn("relative rounded-full border border-error-border bg-background font-mono text-[10px] text-error", connected.includes(WORKFLOW_ROUTE_ERROR) ? "size-2.5 p-0" : "px-1.5 py-px")}
          title={routeWords(WORKFLOW_ROUTE_ERROR)}
        >
          {connected.includes(WORKFLOW_ROUTE_ERROR) ? null : routeWords(WORKFLOW_ROUTE_ERROR)}
          <Handle id={WORKFLOW_ROUTE_ERROR} type="source" position={Position.Bottom} className={cn(HANDLE, "!-bottom-1 !border-error-border")} isConnectable={connectable} />
        </span>
      )}
    </div>
  )
}
