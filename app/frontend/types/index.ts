import type { PageProps } from '@inertiajs/core'
import type { CurrentUser, CurrentWorkspace } from '@/types/serializers'

export type FlashData = {
  notice?: string
  alert?: string
  // Custom flash keys sent via `flash.inertia[:key]` on the server.
  api_key_token?: string
  webhook_signing_secret?: string
  map_events_signing_secret?: string
  // Pages elsewhere the toast points to, such as a provider's settings for what Firefight left there.
  links?: FlashLink[]
}

export type FlashLink = {
  label: string
  url: string
}

export type SharedProps = PageProps & {
  currentUser?: CurrentUser
  currentWorkspace?: CurrentWorkspace
  availableWorkspaces?: CurrentWorkspace[]
  currentUserIsAdmin?: boolean
  pendingApprovalsCount?: number
  // Packs members asked for that wait on an admin, zero for anyone else.
  waitingPackRequestsCount?: number
  agentAvailable?: boolean
  // One flag per Ability::Action resource, whether the viewer may change it.
  currentUserCan?: Record<string, boolean>
  // Set by the cloud engine when loaded, absent on self-hosted builds.
  cloudBillingPath?: string
  // A billing notice from the cloud engine, shown on every dashboard page while it applies.
  cloudBanner?: CloudBanner
  // Set only where the deployment reports browser errors to Sentry.
  errorReporting?: ErrorReportingSettings | null
}

export interface ErrorReportingSettings {
  dsn: string
  environment: string
  release: string | null
}

export interface CloudBanner {
  title: string
  detail: string
  action?: { label: string; href: string }
  // A quiet banner is a note, such as the days left in a trial, rather than something to fix.
  tone?: "quiet"
}

export interface SlackChannel {
  id: string
  name: string
}

export interface Pagination {
  page: number
  perPage: number
  totalCount: number
  totalPages: number
}
