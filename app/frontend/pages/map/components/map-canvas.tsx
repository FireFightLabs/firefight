import "@xyflow/react/dist/style.css"

import { Background, ConnectionLineType, Controls, type Edge, MarkerType, ReactFlow } from "@xyflow/react"
import { useMemo } from "react"

import { ACCOUNT_NODE, type AccountFlowNode, AccountNode } from "@/pages/map/components/account-node"
import { HANDLES, RESOURCE_NODE, type ResourceFlowNode, ResourceNode } from "@/pages/map/components/resource-node"
import { layout } from "@/pages/map/lib/graph"
import { RELATION_WORDS } from "@/pages/map/lib/labels"
import type { ResourceMapLink, ResourceMapResource } from "@/types/serializers"

const NODE_TYPES = { [RESOURCE_NODE]: ResourceNode, [ACCOUNT_NODE]: AccountNode }
const FIT_VIEW = { padding: 0.15, maxZoom: 1.1 }

interface MapCanvasProps {
  resources: ResourceMapResource[]
  links: ResourceMapLink[]
  focusedId?: string | null
  onPick: (resourceId: string) => void
}

// Links drawn solid are facts, reported by a provider or added by a person. A suggestion no one has confirmed is dashed.
export function MapCanvas({ resources, links, focusedId = null, onPick }: MapCanvasProps) {
  const { nodes, edges } = useMemo(() => drawing(resources, links, focusedId), [ resources, links, focusedId ])

  function pickNode(_event: React.MouseEvent, node: ResourceFlowNode | AccountFlowNode) {
    if (node.type === RESOURCE_NODE) {
      onPick(node.id)
    }
  }

  return (
    <ReactFlow
      key={focusedId ?? "map"}
      nodes={nodes}
      edges={edges}
      nodeTypes={NODE_TYPES}
      colorMode="dark"
      fitView
      fitViewOptions={FIT_VIEW}
      minZoom={0.2}
      maxZoom={1.75}
      nodesDraggable={false}
      nodesConnectable={false}
      elementsSelectable={false}
      proOptions={{ hideAttribution: true }}
      onNodeClick={pickNode}
      className="[--xy-background-color:var(--background)] [--xy-controls-button-background-color:var(--card)] [--xy-controls-button-border-color:var(--border)]"
    >
      <Background gap={20} size={1} color="var(--border)" />
      <Controls showInteractive={false} position="bottom-right" />
    </ReactFlow>
  )
}

function drawing(resources: ResourceMapResource[], links: ResourceMapLink[], focusedId: string | null) {
  const placed = layout(resources, links)
  const linked = new Set(links.flatMap((link) => [ link.fromId, link.toId ]))

  const accounts: AccountFlowNode[] = placed.accounts.map(({ account, x, y, width, height }) => ({
    id: `account:${account.key}`,
    type: ACCOUNT_NODE,
    position: { x, y },
    data: { label: account.label, width, height },
    selectable: false,
    zIndex: -1,
  }))
  const nodes: ResourceFlowNode[] = placed.resources.map(({ resource, x, y }) => ({
    id: resource.id,
    type: RESOURCE_NODE,
    position: { x, y },
    data: { resource, focused: resource.id === focusedId, alone: !linked.has(resource.id) },
  }))
  const where = new Map(placed.resources.map((each) => [ each.resource.id, each ]))
  const edges: Edge[] = links.map((link) => ({
    id: link.id,
    ...handles(where.get(link.fromId), where.get(link.toId)),
    type: ConnectionLineType.SmoothStep,
    pathOptions: { borderRadius: 14 },
    source: link.fromId,
    target: link.toId,
    label: RELATION_WORDS[link.relation],
    markerEnd: { type: MarkerType.ArrowClosed, width: 14, height: 14 },
    style: link.unconfirmed
      ? { stroke: "var(--primary)", strokeDasharray: "5 5", strokeWidth: 1.5 }
      : { stroke: "var(--muted-foreground)", strokeWidth: 1.5 },
    labelStyle: { fill: "var(--muted-foreground)", fontSize: 11 },
    labelBgStyle: { fill: "var(--card)" },
    labelBgPadding: [ 6, 3 ] as [number, number],
    labelBgBorderRadius: 8,
  }))

  return { nodes: [ ...accounts, ...nodes ], edges }
}

interface Spot {
  x: number
  y: number
  accountKey: string
}

function handles(from: Spot | undefined, to: Spot | undefined) {
  if (!from || !to || from.accountKey === to.accountKey) {
    return { sourceHandle: HANDLES.OUT_RIGHT, targetHandle: HANDLES.IN_LEFT }
  }
  return from.y < to.y
    ? { sourceHandle: HANDLES.OUT_BOTTOM, targetHandle: HANDLES.IN_TOP }
    : { sourceHandle: HANDLES.OUT_TOP, targetHandle: HANDLES.IN_BOTTOM }
}
