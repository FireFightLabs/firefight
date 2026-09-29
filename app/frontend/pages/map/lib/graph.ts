import dagre from "@dagrejs/dagre"

import type { Depth, Direction, MapFilters } from "@/pages/map/types"
import { DIRECTIONS } from "@/pages/map/types"
import type { ResourceMapLink, ResourceMapResource } from "@/types/serializers"

export const NODE_WIDTH = 216
export const NODE_HEIGHT = 64
const GROUP_PADDING = 20
const GROUP_HEADER = 44

export interface Account {
  key: string
  providerKey: string
  providerName: string
  providerMark?: string
  providerColor?: string
  account: string
  environment?: string
}

export interface Placed {
  resources: { resource: ResourceMapResource; x: number; y: number; accountKey: string }[]
  accounts: { account: Account; x: number; y: number; width: number; height: number }[]
}

export function accountOf(resource: ResourceMapResource): Account {
  return {
    key: `${resource.provider}:${resource.account}`,
    providerKey: resource.provider,
    providerName: resource.providerName,
    providerMark: resource.providerMark,
    providerColor: resource.providerColor,
    account: resource.account,
    environment: resource.environment,
  }
}

export function matchesFilters(resource: ResourceMapResource, filters: MapFilters): boolean {
  const query = filters.query.trim().toLowerCase()
  if (query && ![ resource.name, resource.externalId, resource.account ].some((text) => text.toLowerCase().includes(query))) {
    return false
  }
  if (filters.environment && resource.environment !== filters.environment) {
    return false
  }
  if (filters.provider && resource.provider !== filters.provider) {
    return false
  }
  return !filters.kind || resource.kind === filters.kind
}

// The links among the given resources only, so a filtered map never draws a line to something it hides.
export function linksAmong(links: ResourceMapLink[], ids: Set<string>): ResourceMapLink[] {
  return links.filter((link) => ids.has(link.fromId) && ids.has(link.toId))
}

// Every resource within depth links of the one in focus, walked in the direction asked.
export function neighborhood(focusId: string, links: ResourceMapLink[], depth: Depth, direction: Direction): Set<string> {
  const reached = new Set([ focusId ])
  let frontier = [ focusId ]
  for (let hop = 0; hop < depth; hop += 1) {
    const next: string[] = []
    for (const link of links) {
      const onward = step(link, frontier, direction)
      if (onward && !reached.has(onward)) {
        reached.add(onward)
        next.push(onward)
      }
    }
    frontier = next
  }
  return reached
}

function step(link: ResourceMapLink, frontier: string[], direction: Direction): string | null {
  if (direction !== DIRECTIONS.NEEDED_BY && frontier.includes(link.fromId)) {
    return link.toId
  }
  if (direction !== DIRECTIONS.NEEDS && frontier.includes(link.toId)) {
    return link.fromId
  }
  return null
}

// Everything reads top to bottom in the direction things depend, so resources in the same tier sit side by side and a
// link always runs down between tiers rather than through a card. Each account is laid out on its own and drawn as a
// box around its resources, then the boxes are laid out as a graph of their own, linked where their resources are, so
// no two overlap.
export function layout(resources: ResourceMapResource[], links: ResourceMapLink[]): Placed {
  const byAccount = new Map<string, { account: Account; resources: ResourceMapResource[] }>()
  for (const resource of resources) {
    const account = accountOf(resource)
    const group = byAccount.get(account.key) ?? { account, resources: [] }
    group.resources.push(resource)
    byAccount.set(account.key, group)
  }

  const inner = new Map([ ...byAccount.values() ].map((group) => [ group.account.key, { account: group.account, ...layoutAccount(group.resources, links) } ]))
  const outer = new dagre.graphlib.Graph()
  outer.setGraph({ rankdir: "TB", nodesep: 48, ranksep: 80, marginx: 16, marginy: 16 })
  outer.setDefaultEdgeLabel(() => ({}))
  for (const [ key, box ] of inner) {
    outer.setNode(key, { width: box.width, height: box.height })
  }
  const accountOfId = new Map(resources.map((resource) => [ resource.id, accountOf(resource).key ]))
  for (const link of links) {
    const from = accountOfId.get(link.fromId)
    const to = accountOfId.get(link.toId)
    if (from && to && from !== to) {
      outer.setEdge(from, to)
    }
  }
  dagre.layout(outer)

  const placed: Placed = { resources: [], accounts: [] }
  for (const [ key, box ] of inner) {
    const node = outer.node(key)
    const left = node.x - box.width / 2
    const top = node.y - box.height / 2
    placed.accounts.push({ account: box.account, x: left, y: top, width: box.width, height: box.height })
    for (const each of box.resources) {
      placed.resources.push({ resource: each.resource, x: left + each.x, y: top + each.y, accountKey: key })
    }
  }
  return placed
}

// One account's resources, positioned inside its box with room for the header.
function layoutAccount(resources: ResourceMapResource[], links: ResourceMapLink[]) {
  const graph = new dagre.graphlib.Graph()
  graph.setGraph({ rankdir: "TB", nodesep: 16, ranksep: 56 })
  graph.setDefaultEdgeLabel(() => ({}))
  const ids = new Set(resources.map((resource) => resource.id))
  for (const resource of resources) {
    graph.setNode(resource.id, { width: NODE_WIDTH, height: NODE_HEIGHT })
  }
  for (const link of linksAmong(links, ids)) {
    graph.setEdge(link.fromId, link.toId)
  }
  dagre.layout(graph)

  const nodes = resources.map((resource) => ({ resource, node: graph.node(resource.id) }))
  const left = Math.min(...nodes.map(({ node }) => node.x - NODE_WIDTH / 2))
  const top = Math.min(...nodes.map(({ node }) => node.y - NODE_HEIGHT / 2))
  const right = Math.max(...nodes.map(({ node }) => node.x + NODE_WIDTH / 2))
  const bottom = Math.max(...nodes.map(({ node }) => node.y + NODE_HEIGHT / 2))

  return {
    width: right - left + GROUP_PADDING * 2,
    height: bottom - top + GROUP_PADDING * 2 + GROUP_HEADER,
    resources: nodes.map(({ resource, node }) => ({
      resource,
      x: node.x - NODE_WIDTH / 2 - left + GROUP_PADDING,
      y: node.y - NODE_HEIGHT / 2 - top + GROUP_PADDING + GROUP_HEADER,
    })),
  }
}
