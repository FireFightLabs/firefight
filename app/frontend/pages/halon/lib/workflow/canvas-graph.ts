import dagre from "@dagrejs/dagre"
import type { Edge as FlowEdge, Node } from "@xyflow/react"

import { WORKFLOW_EDIT_OPERATIONS, WORKFLOW_KINDS, WORKFLOW_STEP_STATUS } from "@/lib/generated/constants"
import type { CanvasStep, Edge, StepRunState, Trigger } from "@/pages/halon/lib/workflow/types"
import type { WorkflowDocument, WorkflowStepNode, WorkflowSuggestion } from "@/types/serializers"

export const STEP_NODE = "step"
export const TRIGGER_NODE = "trigger"
export const LOOP_NODE = "loop"
export const ROUTE_EDGE = "route"
export const TRIGGER_ID = "trigger"
// A step's plain way out, beside one handle per route.
export const OUT_HANDLE = "out"
export const IN_HANDLE = "in"

export const STEP_WIDTH = 256
export const STEP_HEIGHT = 84
const LOOP_HEADER = 56
const LOOP_PADDING = 24
const TRIGGER_GAP = 120

export interface StepNodeData extends Record<string, unknown> {
  item: CanvasStep
  // The routes a connection already leaves on, whose labels are on the connections rather than the step.
  connected: string[]
  // Changes by Halon is on and Halon last changed it.
  halonMarked: boolean
  selected: boolean
  readOnly: boolean
}

export interface TriggerNodeData extends Record<string, unknown> {
  trigger: Trigger
  halonMarked: boolean
  selected: boolean
  pending: WorkflowSuggestion[]
}

export interface LoopNodeData extends Record<string, unknown> {
  item: CanvasStep
  connected: string[]
  width: number
  height: number
  halonMarked: boolean
  selected: boolean
  readOnly: boolean
}

export interface RouteEdgeData extends Record<string, unknown> {
  route: string | null
  within: string | null
  // A connection Halon suggests adding, or taking away.
  suggestion: WorkflowSuggestion | null
  halonMarked: boolean
  // The trigger leading to a first step, drawn but never changed.
  implied: boolean
  readOnly: boolean
  // A run went this way: the step it leaves finished and the one it leads to was reached.
  lit: boolean
}

export type StepFlowNode = Node<StepNodeData, typeof STEP_NODE>
export type TriggerFlowNode = Node<TriggerNodeData, typeof TRIGGER_NODE>
export type LoopFlowNode = Node<LoopNodeData, typeof LOOP_NODE>
export type CanvasNode = StepFlowNode | TriggerFlowNode | LoopFlowNode
export type RouteFlowEdge = FlowEdge<RouteEdgeData, typeof ROUTE_EDGE>

interface GraphOptions {
  document: WorkflowDocument
  suggestions: WorkflowSuggestion[]
  highlightHalon: boolean
  selectedId: string | null
  readOnly: boolean
  // Each step's state in the run shown, by its id, when there is one.
  states?: Map<string, StepRunState>
}

const REACHED: readonly string[] = [ WORKFLOW_STEP_STATUS.SUCCEEDED, WORKFLOW_STEP_STATUS.FAILED, WORKFLOW_STEP_STATUS.RUNNING, WORKFLOW_STEP_STATUS.WAITING ]

// Each step with what Halon suggests: a step it would add, and its suggestions to remove, change, move or rename one.
export function canvasSteps(steps: WorkflowStepNode[], suggestions: WorkflowSuggestion[], states?: Map<string, StepRunState>): CanvasStep[] {
  const pendingFor = (id: string) => suggestions.filter((suggestion) => suggestion.stepId === id && suggestion.operation !== WORKFLOW_EDIT_OPERATIONS.ADD_STEP)
  const existing = steps.map((step) => ({ step, suggestion: null, pending: pendingFor(step.id), state: states?.get(step.id) }))
  const added = suggestions.flatMap((suggestion) => (suggestion.addedStep ? [ { step: suggestion.addedStep, suggestion, pending: [] } ] : []))
  return [ ...existing, ...added ]
}

// Every connection with Halon's suggested ones among them, a connection it would take away marked as such.
function canvasEdges(edges: Edge[], suggestions: WorkflowSuggestion[]): { edge: Edge; suggestion: WorkflowSuggestion | null }[] {
  const sameAs = (edge: Edge, other: NonNullable<WorkflowSuggestion["edge"]>) => edge.from === other.from && edge.to === other.to && edge.route === other.route
  const taken = suggestions.filter((suggestion) => suggestion.operation === WORKFLOW_EDIT_OPERATIONS.DISCONNECT)
  const existing = edges.map((edge) => ({ edge, suggestion: taken.find((suggestion) => suggestion.edge && sameAs(edge, suggestion.edge)) ?? null }))
  const added = suggestions.flatMap((suggestion) => {
    if (suggestion.operation !== WORKFLOW_EDIT_OPERATIONS.CONNECT || !suggestion.edge) {
      return []
    }
    return [ { edge: { ...suggestion.edge, changedByHalon: false }, suggestion } ]
  })
  return [ ...existing, ...added ]
}

export function edgeId(edge: Pick<Edge, "from" | "to" | "route">): string {
  return `${edge.from}>${edge.to}:${edge.route ?? ""}`
}

// The picture of a version: the trigger on top, then the steps top to bottom in the direction they run, a for each drawn
// as a box around the steps inside it. A step someone placed keeps its place, and the rest are laid out around them.
export function buildGraph({ document, suggestions, highlightHalon, selectedId, readOnly, states }: GraphOptions): { nodes: CanvasNode[]; edges: RouteFlowEdge[] } {
  const items = canvasSteps(document.steps, suggestions, states)
  const went = (from: string, to: string) => {
    const source = states?.get(from)
    const target = states?.get(to)
    return source?.status === WORKFLOW_STEP_STATUS.SUCCEEDED && target !== undefined && REACHED.includes(target.status)
  }
  const links = canvasEdges(document.edges, suggestions)
  const connected = new Map<string, string[]>()
  for (const { edge } of links) {
    if (edge.route) {
      connected.set(edge.from, [ ...(connected.get(edge.from) ?? []), edge.route ])
    }
  }
  const options = { highlightHalon, selectedId, readOnly, connected }
  const top = placeLevel(null, items, links, options)
  const nodes: CanvasNode[] = [ ...top.nodes ]

  const topEdges = links.filter(({ edge }) => !edge.within).map(({ edge }) => edge)
  // A step Halon only suggests is not where a run starts until someone accepts it.
  const starts = top.placed.filter(({ item }) => !item.suggestion && !topEdges.some((edge) => edge.to === item.step.id))
  const triggerX = starts.length > 0 ? starts.reduce((sum, { x, width }) => sum + x + width / 2, 0) / starts.length - STEP_WIDTH / 2 : 0
  const triggerY = starts.length > 0 ? Math.min(...starts.map((start) => start.y)) - TRIGGER_GAP : 0
  nodes.unshift({
    id: TRIGGER_ID,
    type: TRIGGER_NODE,
    position: { x: triggerX, y: triggerY },
    data: {
      trigger: document.trigger,
      halonMarked: highlightHalon && document.triggerChangedByHalon,
      selected: selectedId === TRIGGER_ID,
      pending: suggestions.filter((suggestion) => suggestion.operation === WORKFLOW_EDIT_OPERATIONS.CHANGE_TRIGGER),
    },
    draggable: false,
  })

  const edges: RouteFlowEdge[] = links.map(({ edge, suggestion }) => ({
    id: suggestion ? `${suggestion.id}:${edgeId(edge)}` : edgeId(edge),
    type: ROUTE_EDGE,
    source: edge.from,
    target: edge.to,
    sourceHandle: edge.route ?? OUT_HANDLE,
    targetHandle: IN_HANDLE,
    data: { route: edge.route, within: edge.within, suggestion, halonMarked: highlightHalon && edge.changedByHalon, implied: false, readOnly, lit: went(edge.from, edge.to) },
    selectable: !readOnly && !suggestion,
    zIndex: 1,
  }))
  for (const start of starts) {
    edges.push({
      id: `${TRIGGER_ID}>${start.item.step.id}`,
      type: ROUTE_EDGE,
      source: TRIGGER_ID,
      target: start.item.step.id,
      sourceHandle: OUT_HANDLE,
      targetHandle: IN_HANDLE,
      data: { route: null, within: null, suggestion: null, halonMarked: false, implied: true, readOnly: true, lit: REACHED.includes(states?.get(start.item.step.id)?.status ?? "") },
      selectable: false,
    })
  }
  return { nodes, edges }
}

interface LevelOptions {
  highlightHalon: boolean
  selectedId: string | null
  readOnly: boolean
  connected: Map<string, string[]>
}

interface Placed {
  item: CanvasStep
  x: number
  y: number
  width: number
  height: number
  // Placed by someone, where React Flow said it was, so inside a for each it is already past the box's header.
  fixed: boolean
}

// One level of steps, the top or the inside of a for each, with each for each inside it laid out first so its box is
// the size of what it holds. A box comes before the steps inside it, as React Flow needs a parent before its children.
function placeLevel(within: string | null, items: CanvasStep[], links: { edge: Edge }[], options: LevelOptions): { placed: Placed[]; nodes: CanvasNode[] } {
  const level = items.filter((item) => (item.step.within ?? null) === within)
  const sizes = new Map<string, { width: number; height: number }>()
  const inner = new Map<string, CanvasNode[]>()
  for (const loop of level.filter((item) => item.step.kind === WORKFLOW_KINDS.FOR_EACH)) {
    const child = placeLevel(loop.step.id, items, links, options)
    const width = Math.max(STEP_WIDTH + LOOP_PADDING * 2, ...child.placed.map(({ x, width: each }) => x + each + LOOP_PADDING * 2))
    const height = Math.max(LOOP_HEADER + STEP_HEIGHT + LOOP_PADDING * 2, ...child.placed.map(({ y, height: each }) => y + each + LOOP_HEADER + LOOP_PADDING * 2))
    sizes.set(loop.step.id, { width, height })
    inner.set(loop.step.id, child.nodes)
  }

  const placed = layout(level, links.filter(({ edge }) => (edge.within ?? null) === within).map(({ edge }) => edge), within === null, sizes)
  const offset = within ? { x: LOOP_PADDING, y: LOOP_HEADER + LOOP_PADDING } : { x: 0, y: 0 }
  const nodes: CanvasNode[] = []
  for (const each of placed) {
    const position = each.fixed ? { x: each.x, y: each.y } : { x: each.x + offset.x, y: each.y + offset.y }
    const size = sizes.get(each.item.step.id)
    if (size) {
      nodes.push({
        id: each.item.step.id,
        type: LOOP_NODE,
        position,
        parentId: within ?? undefined,
        extent: within ? "parent" : undefined,
        data: {
          item: each.item, ...size, connected: options.connected.get(each.item.step.id) ?? [], halonMarked: options.highlightHalon && each.item.step.changedByHalon,
          selected: each.item.step.id === options.selectedId, readOnly: options.readOnly || each.item.suggestion !== null,
        },
        style: { width: size.width, height: size.height },
        draggable: !options.readOnly && each.item.suggestion === null,
      })
      nodes.push(...(inner.get(each.item.step.id) ?? []))
    } else {
      nodes.push(stepNode(each.item, position, { ...options, parentId: within ?? undefined }))
    }
  }
  return { placed, nodes }
}

function stepNode(item: CanvasStep, position: { x: number; y: number }, options: LevelOptions & { parentId?: string }): StepFlowNode {
  return {
    id: item.step.id,
    type: STEP_NODE,
    position,
    parentId: options.parentId,
    extent: options.parentId ? "parent" : undefined,
    data: {
      item,
      connected: options.connected.get(item.step.id) ?? [],
      halonMarked: options.highlightHalon && item.step.changedByHalon,
      selected: item.step.id === options.selectedId,
      readOnly: options.readOnly || item.suggestion !== null,
    },
    draggable: !options.readOnly && item.suggestion === null,
  }
}

// Positions for the steps of one level, dagre's where nobody placed a step and the saved place where someone did.
function layout(items: CanvasStep[], edges: Edge[], leaveRoomForTrigger: boolean, sizes: Map<string, { width: number; height: number }>): Placed[] {
  const graph = new dagre.graphlib.Graph()
  graph.setGraph({ rankdir: "TB", nodesep: 40, ranksep: 64, marginx: 0, marginy: leaveRoomForTrigger ? TRIGGER_GAP : 0 })
  graph.setDefaultEdgeLabel(() => ({}))
  const ids = new Set(items.map((item) => item.step.id))
  for (const item of items) {
    const size = sizes.get(item.step.id) ?? { width: STEP_WIDTH, height: STEP_HEIGHT }
    graph.setNode(item.step.id, size)
  }
  for (const edge of edges) {
    if (ids.has(edge.from) && ids.has(edge.to)) {
      graph.setEdge(edge.from, edge.to)
    }
  }
  dagre.layout(graph)
  return items.map((item) => {
    const node = graph.node(item.step.id)
    const size = sizes.get(item.step.id) ?? { width: STEP_WIDTH, height: STEP_HEIGHT }
    const saved = item.step.position
    return { item, x: saved ? saved.x : node.x - size.width / 2, y: saved ? saved.y : node.y - size.height / 2, ...size, fixed: Boolean(saved) }
  })
}
