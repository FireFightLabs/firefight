import type { ResourceMapChangeKind, ResourceMapKind, ResourceMapOrigin, ResourceMapRelation } from "@/lib/generated/constants"
import type { ResourceMapChange, ResourceMapLink } from "@/types/serializers"

export const KIND_LABELS: Record<ResourceMapKind, string> = {
  service: "Service",
  build_service: "Build service",
  job: "Job",
  database: "Database",
  branch: "Database branch",
  repository: "Repository",
  domain: "Domain",
}

// Read between the two names, as in "web runs builds of firefight".
export const RELATION_SENTENCES: Record<ResourceMapRelation, string> = {
  runs_builds_of: "runs builds of",
  built_from: "is built from",
  served_by: "is served by",
  branch_of: "is a branch of",
  uses: "uses",
}

// The short word drawn on a link.
export const RELATION_WORDS: Record<ResourceMapRelation, string> = {
  runs_builds_of: "runs",
  built_from: "built from",
  served_by: "served by",
  branch_of: "branch of",
  uses: "uses",
}

const HOW_FOUND: Record<ResourceMapOrigin, (link: ResourceMapLink) => string> = {
  declared: (link) => `Declared by ${link.foundBy ?? "a connection"}`,
  matched: (link) => `Matched from what ${link.foundBy ?? "a connection"} reports`,
  person: () => "Added by a person",
  suggested: (link) => (link.unconfirmed ? "Suggested by Halon, not confirmed yet" : "Suggested by Halon, confirmed"),
}

export function howFound(link: ResourceMapLink): string {
  return HOW_FOUND[link.origin](link)
}

const CHANGE_LABELS: Record<ResourceMapChangeKind, (change: ResourceMapChange) => string> = {
  appeared: (change) => `${change.resourceName} appeared`,
  removed: (change) => `${change.resourceName} is gone`,
  deployed: (change) => `${change.resourceName} deployed ${shortCommit(change.toValue)}`,
  status_changed: (change) => `${change.resourceName} went from ${change.fromValue ?? "unknown"} to ${change.toValue ?? "unknown"}`,
}

export function changeLabel(change: ResourceMapChange): string {
  return CHANGE_LABELS[change.kind](change)
}

export function shortCommit(sha: string | undefined): string {
  return sha ? sha.slice(0, 7) : "a new build"
}
