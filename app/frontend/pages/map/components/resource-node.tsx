import { Handle, type Node, type NodeProps, Position } from "@xyflow/react"

import { cn } from "@/lib/utils"
import { KIND_ICONS } from "@/pages/map/lib/icons"
import { KIND_LABELS } from "@/pages/map/lib/labels"
import type { ResourceMapResource } from "@/types/serializers"

export type ResourceNodeData = {
  resource: ResourceMapResource
  focused: boolean
  alone: boolean
}

export const RESOURCE_NODE = "resource"

// Links inside an account run left to right, and links between accounts, which are stacked, run top to bottom.
export const HANDLES = {
  IN_LEFT: "in-left",
  OUT_RIGHT: "out-right",
  IN_TOP: "in-top",
  OUT_TOP: "out-top",
  IN_BOTTOM: "in-bottom",
  OUT_BOTTOM: "out-bottom",
} as const

const HANDLE_CLASS = "!size-1.5 !min-h-0 !min-w-0 !border-0 !bg-transparent"

export type ResourceFlowNode = Node<ResourceNodeData, typeof RESOURCE_NODE>

// A resource on the canvas. An open incident rings it red, and one with no links is drawn quieter, since nothing on the
// map is known to depend on it or it on anything.
export function ResourceNode({ data }: NodeProps<ResourceFlowNode>) {
  const { resource, focused, alone } = data
  const KindIcon = KIND_ICONS[resource.kind]
  const incident = resource.openIncidents[0]
  const moreIncidents = resource.openIncidents.length - 1

  return (
    <div
      className={cn(
        "flex h-16 w-[216px] items-center gap-3 rounded-xl border bg-card px-3 shadow-sm transition-colors",
        incident ? "border-destructive/70 ring-4 ring-destructive/15" : "border-border hover:border-foreground/30",
        focused && !incident && "border-primary ring-4 ring-primary/15",
        alone && !incident && !focused && "border-dashed opacity-75",
      )}
    >
      <Handle id={HANDLES.IN_LEFT} type="target" position={Position.Left} className={HANDLE_CLASS} isConnectable={false} />
      <Handle id={HANDLES.IN_TOP} type="target" position={Position.Top} className={HANDLE_CLASS} isConnectable={false} />
      <Handle id={HANDLES.OUT_TOP} type="source" position={Position.Top} className={HANDLE_CLASS} isConnectable={false} />
      <span
        className={cn(
          "flex size-9 shrink-0 items-center justify-center rounded-lg",
          incident ? "bg-destructive/15 text-destructive" : "bg-muted text-foreground/80",
        )}
      >
        <KindIcon className="size-[18px]" stroke={1.8} />
      </span>
      <span className="flex min-w-0 flex-col leading-tight">
        <span className="truncate text-[13.5px] font-semibold text-foreground">{resource.name}</span>
        <span className={cn("truncate text-xs", incident ? "text-destructive" : "text-muted-foreground")}>
          {incident ? `${incident.identifier} open${moreIncidents > 0 ? ` +${moreIncidents}` : ""}` : subtitle(resource)}
        </span>
      </span>
      <Handle id={HANDLES.OUT_RIGHT} type="source" position={Position.Right} className={HANDLE_CLASS} isConnectable={false} />
      <Handle id={HANDLES.IN_BOTTOM} type="target" position={Position.Bottom} className={HANDLE_CLASS} isConnectable={false} />
      <Handle id={HANDLES.OUT_BOTTOM} type="source" position={Position.Bottom} className={HANDLE_CLASS} isConnectable={false} />
    </div>
  )
}

function subtitle(resource: ResourceMapResource): string {
  return [ KIND_LABELS[resource.kind], resource.status ].filter(Boolean).join(" · ")
}
