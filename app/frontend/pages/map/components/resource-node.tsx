import { Handle, type Node, type NodeProps, Position } from "@xyflow/react"

import { cn } from "@/lib/utils"
import { KIND_ICONS } from "@/pages/map/lib/icons"
import { KIND_LABELS } from "@/pages/map/lib/labels"
import { HEALTH_DOTS, KIND_TONES } from "@/pages/map/lib/tones"
import type { ResourceMapResource } from "@/types/serializers"

export const RESOURCE_NODE = "resource"

// Links run top to bottom, into a card's top and out of its bottom.
export const HANDLES = { IN: "in", OUT: "out" } as const

const HANDLE_CLASS = "!size-1.5 !min-h-0 !min-w-0 !border-0 !bg-transparent"

export type ResourceNodeData = {
  resource: ResourceMapResource
  focused: boolean
  alone: boolean
}

export type ResourceFlowNode = Node<ResourceNodeData, typeof RESOURCE_NODE>

// A resource on the canvas. An open incident rings it red, the one in focus is ringed in the accent, and one with no
// links is drawn quieter, since nothing on the map is known to depend on it or it on anything.
export function ResourceNode({ data }: NodeProps<ResourceFlowNode>) {
  const { resource, focused, alone } = data
  const KindIcon = KIND_ICONS[resource.kind]
  const incident = resource.openIncidents[0]
  const moreIncidents = resource.openIncidents.length - 1

  return (
    <div
      className={cn(
        "group flex h-16 w-[216px] items-center gap-3 rounded-xl border bg-gradient-to-b from-card to-card/70 px-3 shadow-[0_1px_0_0_rgba(255,255,255,0.04)_inset,0_8px_24px_-12px_rgba(0,0,0,0.6)] transition-[border-color,box-shadow,transform] duration-150 hover:-translate-y-px",
        incident ? "border-destructive/60 ring-4 ring-destructive/15" : "border-border/80 hover:border-foreground/25",
        focused && !incident && "border-primary/70 ring-4 ring-primary/15",
        alone && !incident && !focused && "border-dashed opacity-80",
      )}
    >
      <Handle id={HANDLES.IN} type="target" position={Position.Top} className={HANDLE_CLASS} isConnectable={false} />
      <span className={cn("flex size-9 shrink-0 items-center justify-center rounded-lg ring-1 ring-inset", incident ? "bg-destructive/15 text-destructive ring-destructive/30" : KIND_TONES[resource.kind])}>
        <KindIcon className="size-[18px]" stroke={1.7} />
      </span>
      <span className="flex min-w-0 grow flex-col gap-0.5 leading-tight">
        <span className="truncate text-[13px] font-semibold tracking-tight text-foreground">{resource.name}</span>
        <span className={cn("flex items-center gap-1.5 truncate text-[11.5px]", incident ? "text-destructive" : "text-muted-foreground")}>
          {incident ? (
            `${incident.identifier} open${moreIncidents > 0 ? ` +${moreIncidents}` : ""}`
          ) : (
            <>
              <span className={cn("size-1.5 shrink-0 rounded-full", HEALTH_DOTS[resource.health])} />
              <span className="truncate">{resource.statusLabel ?? KIND_LABELS[resource.kind]}</span>
            </>
          )}
        </span>
      </span>
      <Handle id={HANDLES.OUT} type="source" position={Position.Bottom} className={HANDLE_CLASS} isConnectable={false} />
    </div>
  )
}
