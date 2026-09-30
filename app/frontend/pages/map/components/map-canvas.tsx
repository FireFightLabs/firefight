import "@xyflow/react/dist/style.css"

import { Background, ConnectionLineType, Controls, type Edge, MarkerType, ReactFlow } from "@xyflow/react"
import { useMemo } from "react"

import { ACCOUNT_NODE, type AccountFlowNode, AccountNode } from "@/pages/map/components/account-node"
import { HANDLES, RESOURCE_NODE, type ResourceFlowNode, ResourceNode } from "@/pages/map/components/resource-node"
import { layout } from "@/pages/map/lib/graph"
import { RESOURCE_MAP_CERTAINTY } from "@/lib/generated/constants"
import { CERTAINTY_LABELS, RELATION_WORDS } from "@/pages/map/lib/labels"
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
  const counts = new Map<string, number>()
  for (const each of placed.resources) {
    counts.set(each.accountKey, (counts.get(each.accountKey) ?? 0) + 1)
  }

  const accounts: AccountFlowNode[] = placed.accounts.map(({ account, x, y, width, height }) => ({
    id: `account:${account.key}`,
    type: ACCOUNT_NODE,
    position: { x, y },
    data: { ...account, count: counts.get(account.key) ?? 0, width, height },
    selectable: false,
    zIndex: -1,
  }))
  const nodes: ResourceFlowNode[] = placed.resources.map(({ resource, x, y }) => ({
    id: resource.id,
    type: RESOURCE_NODE,
    position: { x, y },
    data: { resource, focused: resource.id === focusedId, alone: !linked.has(resource.id) },
  }))

  // Several links into one resource for the same reason share their last stretch, so only one carries the word.
  const labelled = new Set<string>()
  const edges: Edge[] = links.map((link) => {
    const group = `${link.toId}:${link.relation}`
    const word = link.unconfirmed ? `${RELATION_WORDS[link.relation]}?` : RELATION_WORDS[link.relation]
    const label = labelled.has(group) ? undefined : link.certainty && link.unconfirmed ? `${word} (${CERTAINTY_LABELS[link.certainty].toLowerCase()})` : word
    labelled.add(group)
    const tone = link.unconfirmed ? "var(--primary)" : "color-mix(in oklch, var(--muted-foreground) 70%, transparent)"
    return {
      id: link.id,
      type: ConnectionLineType.Bezier,
      source: link.fromId,
      target: link.toId,
      sourceHandle: HANDLES.OUT,
      targetHandle: HANDLES.IN,
      label,
      markerEnd: { type: MarkerType.ArrowClosed, width: 12, height: 12, color: tone },
      style: { stroke: tone, strokeWidth: 1.4, strokeDasharray: dashes(link), opacity: link.unconfirmed && link.certainty === POSSIBLE ? 0.6 : 1 },
      labelStyle: { fill: "var(--muted-foreground)", fontSize: 10.5, fontWeight: 500 },
      labelBgStyle: { fill: "var(--background)", stroke: "var(--border)", strokeWidth: 1 },
      labelBgPadding: [ 7, 3 ] as [number, number],
      labelBgBorderRadius: 999,
    }
  })

  return { nodes: [ ...accounts, ...nodes ], edges }
}

const POSSIBLE = RESOURCE_MAP_CERTAINTY.POSSIBLE

// A fact is a solid line. A likely suggestion is dashed, and a possible one dotted and fainter, since it rests on one clue.
function dashes(link: ResourceMapLink): string | undefined {
  if (!link.unconfirmed) {
    return undefined
  }
  return link.certainty === POSSIBLE ? "2 5" : "6 5"
}
