import {
  IconAlertTriangle,
  IconArrowsJoin,
  IconArrowsSplit,
  IconBell,
  IconBellRinging,
  IconBolt,
  IconBook,
  IconBroadcast,
  IconBrowser,
  IconCalendarRepeat,
  IconCategory,
  IconCircleX,
  IconClock,
  IconCode,
  IconDatabase,
  IconEye,
  IconFlame,
  IconHandClick,
  IconHash,
  IconHourglass,
  IconListCheck,
  IconMessage,
  IconPlayerStop,
  IconRepeat,
  IconRocket,
  IconSitemap,
  IconShieldLock,
  IconSparkles,
  IconTerminal2,
  IconTicket,
  IconTool,
  IconTopologyStar3,
  IconUserCheck,
  IconUser,
  IconWebhook,
  IconWorld,
  IconZoomQuestion,
  type Icon,
} from "@tabler/icons-react"

import type {
  WorkflowBackoff,
  WorkflowConditionOperator,
  WorkflowDelayUnit,
  WorkflowJoinMode,
  WorkflowOnFailure,
  WorkflowStepGroup,
  WorkflowStepIcon,
  WorkflowTriggerIcon,
} from "@/lib/generated/constants"

// The groups of the Steps table, in the palette's words.
export const GROUP_LABELS: Record<WorkflowStepGroup, string> = {
  halon: "Halon",
  tools: "Tools",
  incident: "Incident",
  messages: "Tell people",
  sandbox: "Sandbox",
  http: "HTTP",
  waiting: "Waiting",
  people: "People",
  control: "Flow",
  by_hand: "By hand",
}

export const STEP_ICONS: Record<WorkflowStepIcon, Icon> = {
  branch: IconArrowsSplit,
  delay: IconHourglass,
  event: IconBolt,
  loop: IconRepeat,
  join: IconArrowsJoin,
  workflow: IconSitemap,
  tool: IconTool,
  halon: IconSparkles,
  message: IconMessage,
  channel: IconHash,
  incident: IconFlame,
  notice: IconBell,
  watch: IconEye,
  skill: IconBook,
  terminal: IconTerminal2,
  globe: IconWorld,
  person: IconUser,
  approval: IconUserCheck,
  stop: IconPlayerStop,
  investigate: IconZoomQuestion,
  classify: IconCategory,
  page: IconBellRinging,
  follow_up: IconListCheck,
  status_page: IconBroadcast,
  script: IconCode,
  browser: IconBrowser,
  webhook: IconWebhook,
  data: IconDatabase,
}


export const TRIGGER_ICONS: Record<WorkflowTriggerIcon, Icon> = {
  hand: IconHandClick,
  schedule: IconCalendarRepeat,
  clock: IconClock,
  incident: IconFlame,
  alert: IconAlertTriangle,
  webhook: IconWebhook,
  deploy: IconRocket,
  halon: IconSparkles,
  workflow: IconSitemap,
  follow_up: IconListCheck,
  failed: IconCircleX,
  map: IconTopologyStar3,
  security: IconShieldLock,
  issue: IconTicket,
}

export const OPERATOR_LABELS: Record<WorkflowConditionOperator, string> = {
  equals: "is",
  not_equals: "is not",
  is_one_of: "is one of",
  contains: "contains",
  starts_with: "starts with",
  matches_regex: "matches the pattern",
  is_empty: "is empty",
  is_not_empty: "is not empty",
  greater_than: "is more than",
  greater_or_equal: "is at least",
  less_than: "is less than",
  less_or_equal: "is at most",
}

export const ON_FAILURE_LABELS: Record<WorkflowOnFailure, string> = {
  stop: "Stop the run",
  continue: "Carry on with the next steps",
  error_route: "Take the error path",
}

export const BACKOFF_LABELS: Record<WorkflowBackoff, string> = {
  exponential: "Longer each time",
  linear: "A little longer each time",
  fixed: "The same wait each time",
}

export const DELAY_UNIT_LABELS: Record<WorkflowDelayUnit, string> = {
  seconds: "Seconds",
  minutes: "Minutes",
  hours: "Hours",
  days: "Days",
}

export const JOIN_MODE_LABELS: Record<WorkflowJoinMode, string> = {
  all: "Wait for every path",
  first: "Go on with the first path",
}

export const EFFECT_LABELS = { reads: "Reads", changes: "Changes" } as const

// A route as an edge's label reads it, timed_out as timed out.
export function routeWords(route: string): string {
  return route.split("_").join(" ")
}
