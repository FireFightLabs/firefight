import type { ResourceMapHealth, ResourceMapKind } from "@/lib/generated/constants"

// One colour per kind of resource, so a database reads apart from a service at a glance.
export const KIND_TONES: Record<ResourceMapKind, string> = {
  service: "bg-sky-500/15 text-sky-300 ring-sky-400/25",
  build_service: "bg-amber-500/15 text-amber-300 ring-amber-400/25",
  job: "bg-indigo-500/15 text-indigo-300 ring-indigo-400/25",
  database: "bg-violet-500/15 text-violet-300 ring-violet-400/25",
  branch: "bg-fuchsia-500/15 text-fuchsia-300 ring-fuchsia-400/25",
  repository: "bg-slate-400/15 text-slate-200 ring-slate-300/20",
  domain: "bg-teal-500/15 text-teal-300 ring-teal-400/25",
}

export const HEALTH_DOTS: Record<ResourceMapHealth, string> = {
  ok: "bg-emerald-400 shadow-[0_0_0_3px] shadow-emerald-400/15",
  busy: "bg-amber-400 shadow-[0_0_0_3px] shadow-amber-400/15",
  failing: "bg-red-400 shadow-[0_0_0_3px] shadow-red-400/20",
  unknown: "bg-muted-foreground/50",
}
