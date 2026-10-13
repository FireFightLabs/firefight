import "@xyflow/react/dist/style.css"

import {
  Background,
  BackgroundVariant,
  type Connection,
  MarkerType,
  type NodeMouseHandler,
  type OnBeforeDelete,
  type OnNodeDrag,
  ReactFlow,
  useNodesState,
  useReactFlow,
} from "@xyflow/react"
import { type DragEvent, useEffect, useMemo, useRef } from "react"

import { WORKFLOW_EDIT_OPERATIONS } from "@/lib/generated/constants"
import { LoopNode } from "@/pages/halon/components/workflow/loop-node"
import { RouteEdge } from "@/pages/halon/components/workflow/route-edge"
import { StepNode } from "@/pages/halon/components/workflow/step-node"
import { TriggerNode } from "@/pages/halon/components/workflow/trigger-node"
import type { AddAt } from "@/pages/halon/hooks/use-add-step"
import type { SendEdit } from "@/pages/halon/hooks/use-workflow-edits"
import {
  buildGraph,
  type CanvasNode,
  LOOP_NODE,
  OUT_HANDLE,
  ROUTE_EDGE,
  type RouteFlowEdge,
  STEP_HEIGHT,
  STEP_NODE,
  STEP_WIDTH,
  TRIGGER_ID,
  TRIGGER_NODE,
} from "@/pages/halon/lib/workflow/canvas-graph"
import { DRAG_TYPE, type PaletteChoice } from "@/pages/halon/lib/workflow/new-step"
import type { Selection, StepRunState } from "@/pages/halon/lib/workflow/types"
import type { WorkflowDocument, WorkflowStepKind, WorkflowSuggestion, WorkflowToolChoice } from "@/types/serializers"

const NODE_TYPES = { [STEP_NODE]: StepNode, [TRIGGER_NODE]: TriggerNode, [LOOP_NODE]: LoopNode }
const EDGE_TYPES = { [ROUTE_EDGE]: RouteEdge }
const FIT_VIEW = { padding: 0.2, maxZoom: 1 }
const DEFAULT_EDGE = { markerEnd: { type: MarkerType.ArrowClosed, width: 12, height: 12, color: "var(--border-control)" } }

interface FlowCanvasProps {
  document: WorkflowDocument
  suggestions: WorkflowSuggestion[]
  stepKinds: WorkflowStepKind[]
  tools: WorkflowToolChoice[]
  highlightHalon: boolean
  selection: Selection
  readOnly: boolean
  states?: Map<string, StepRunState>
  send: SendEdit
  onSelect: (selection: Selection) => void
  onAdd: (choice: PaletteChoice, at: AddAt) => void
}

// The workflow drawn as a graph. Steps are dragged to move them, connected by dragging from a way out to another step,
// and a connection is taken away with its button or the delete key. A step dropped from the palette lands where it was
// let go, inside a for each when it was let go in one. Each change is sent as one edit and the canvas redraws from what
// the server kept.
export function FlowCanvas({ document, suggestions, stepKinds, tools, highlightHalon, selection, readOnly, states, send, onSelect, onAdd }: FlowCanvasProps) {
  const { screenToFlowPosition, getIntersectingNodes, getInternalNode } = useReactFlow<CanvasNode, RouteFlowEdge>()
  const selectedId = selection?.kind === "step" ? selection.id : selection?.kind === "trigger" ? TRIGGER_ID : null
  const graph = useMemo(
    () => buildGraph({ document, suggestions, highlightHalon, selectedId, readOnly, states }),
    [ document, suggestions, highlightHalon, selectedId, readOnly, states ],
  )
  const [ nodes, setNodes, onNodesChange ] = useNodesState<CanvasNode>(graph.nodes)

  // A reload landing mid drag would put the step back where it was saved, so it waits until the step is let go.
  const dragging = useRef(false)
  const missed = useRef(false)

  useEffect(() => {
    if (dragging.current) {
      missed.current = true
      return
    }
    setNodes(graph.nodes)
  }, [ graph.nodes, setNodes ])

  function dragStarted() {
    dragging.current = true
  }

  const pickNode: NodeMouseHandler<CanvasNode> = (_event, node) => {
    onSelect(node.id === TRIGGER_ID ? { kind: "trigger" } : { kind: "step", id: node.id })
  }

  function clearSelection() {
    onSelect(null)
  }

  const moved: OnNodeDrag<CanvasNode> = (_event, node) => {
    dragging.current = false
    const before = graph.nodes.find((each) => each.id === node.id)
    if (!before || (before.position.x === node.position.x && before.position.y === node.position.y)) {
      if (missed.current) {
        missed.current = false
        setNodes(graph.nodes)
      }
      return
    }
    missed.current = false
    send(WORKFLOW_EDIT_OPERATIONS.MOVE_STEP, { step_id: node.id, position: { x: Math.round(node.position.x), y: Math.round(node.position.y) } })
  }

  function connect(connection: Connection) {
    const source = nodes.find((node) => node.id === connection.source)
    const route = connection.sourceHandle && connection.sourceHandle !== OUT_HANDLE ? connection.sourceHandle : null
    const edge = { from: connection.source, to: connection.target, route }
    send(WORKFLOW_EDIT_OPERATIONS.CONNECT, source?.parentId ? { ...edge, within: source.parentId } : edge)
  }

  // Only connections are taken away from the keyboard, since removing a step asks first in its settings.
  const beforeDelete: OnBeforeDelete<CanvasNode, RouteFlowEdge> = async ({ edges }) => {
    edges.filter((edge) => edge.data && !edge.data.implied && !edge.data.suggestion).forEach((edge) => {
      const payload = { from: edge.source, to: edge.target, route: edge.data?.route ?? null }
      send(WORKFLOW_EDIT_OPERATIONS.DISCONNECT, edge.data?.within ? { ...payload, within: edge.data.within } : payload)
    })
    return false
  }

  function allowDrop(event: DragEvent) {
    if (event.dataTransfer.types.includes(DRAG_TYPE)) {
      event.preventDefault()
      event.dataTransfer.dropEffect = "copy"
    }
  }

  function drop(event: DragEvent) {
    const raw = event.dataTransfer.getData(DRAG_TYPE)
    if (!raw || readOnly) {
      return
    }
    event.preventDefault()
    const dropped: { kind: string; tool: string | null } = JSON.parse(raw)
    const kind = stepKinds.find((each) => each.key === dropped.kind)
    if (!kind) {
      return
    }
    const tool = dropped.tool ? tools.find((each) => each.name === dropped.tool) ?? null : null
    const pointer = screenToFlowPosition({ x: event.clientX, y: event.clientY })
    const point = { x: pointer.x - STEP_WIDTH / 2, y: pointer.y - STEP_HEIGHT / 2 }
    const loops = getIntersectingNodes({ x: pointer.x, y: pointer.y, width: 1, height: 1 }).filter((node) => node.type === LOOP_NODE)
    // The innermost box it was let go in, since a for each may sit inside another.
    const loop = loops[loops.length - 1]
    const origin = loop ? getInternalNode(loop.id)?.internals.positionAbsolute : undefined
    const position = loop && origin ? { x: point.x - origin.x, y: point.y - origin.y } : point
    onAdd({ kind, tool }, { position, within: loop?.id ?? null })
  }

  return (
    <ReactFlow<CanvasNode, RouteFlowEdge>
      nodes={nodes}
      edges={graph.edges}
      nodeTypes={NODE_TYPES}
      edgeTypes={EDGE_TYPES}
      defaultEdgeOptions={DEFAULT_EDGE}
      colorMode="dark"
      fitView
      fitViewOptions={FIT_VIEW}
      minZoom={0.25}
      maxZoom={1.75}
      nodesDraggable={!readOnly}
      nodesConnectable={!readOnly}
      elementsSelectable
      deleteKeyCode={readOnly ? null : [ "Backspace", "Delete" ]}
      proOptions={{ hideAttribution: true }}
      onNodesChange={onNodesChange}
      onNodeClick={pickNode}
      onPaneClick={clearSelection}
      onNodeDragStart={dragStarted}
      onNodeDragStop={moved}
      onConnect={connect}
      onBeforeDelete={beforeDelete}
      onDragOver={allowDrop}
      onDrop={drop}
      className="[--xy-background-color:var(--background)]"
    >
      <Background variant={BackgroundVariant.Dots} gap={24} size={1.2} color="var(--border-strong)" />
    </ReactFlow>
  )
}
