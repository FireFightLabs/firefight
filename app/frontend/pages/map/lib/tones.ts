import type { ResourceMapHealth, ResourceMapKind } from "@/lib/generated/constants"

// One chart colour per family of resource, so a database reads apart from a service at a glance.
// Lime is left out, since on this page it means healthy.
const SERVING = "bg-stage-active-tint text-chart-2 ring-stage-active-border"
const ROUTING = "bg-surface-selected text-fg-body ring-border-strong"
const STORING = "bg-stage-triage-tint text-chart-3 ring-stage-triage-border"
const RUNNING = "bg-warning-tint text-chart-4 ring-warning/30"
const SOURCE = "bg-stage-canceled-tint text-chart-5 ring-stage-canceled-border"

export const KIND_TONES: Record<ResourceMapKind, string> = {
  service: SERVING,
  build_service: RUNNING,
  job: RUNNING,
  database: STORING,
  branch: SOURCE,
  repository: SOURCE,
  domain: ROUTING,
  zone: ROUTING,
  worker: RUNNING,
  site: SERVING,
  bucket: STORING,
  kv_namespace: STORING,
  queue: RUNNING,
  database_proxy: STORING,
  tunnel: ROUTING,
  load_balancer: ROUTING,
  origin_pool: ROUTING,
  access_app: SERVING,
}

export const HEALTH_DOTS: Record<ResourceMapHealth, string> = {
  ok: "bg-success",
  busy: "bg-warning",
  failing: "bg-error",
  unknown: "bg-fg-disabled",
}
