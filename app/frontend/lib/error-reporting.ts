import { init, type Breadcrumb, type ErrorEvent } from "@sentry/react"

import type { ErrorReportingSettings } from "@/types"

type Integration = { name: string }

// Errors only. Sessions and console output are never sent, and no tracing or replay is added.
const LEFT_OUT = new Set(["BrowserSession", "Console"])

// A query can carry a sign-in token, so no address leaves the page with one.
const URL_FIELDS = ["url", "from", "to"]

function withoutQuery(url: string): string {
  return url.split(/[?#]/)[0]
}

function keptIntegrations<Kind extends Integration>(defaults: Kind[]): Kind[] {
  return defaults.filter((integration) => !LEFT_OUT.has(integration.name))
}

function scrubEvent(event: ErrorEvent): ErrorEvent {
  const request = event.request
  if (!request?.url) {
    return event
  }

  return { ...event, request: { ...request, url: withoutQuery(request.url), query_string: undefined } }
}

function scrubBreadcrumb(breadcrumb: Breadcrumb): Breadcrumb {
  const data = breadcrumb.data
  if (!data) {
    return breadcrumb
  }

  const scrubbed = { ...data }
  URL_FIELDS.forEach((field) => {
    const value: unknown = scrubbed[field]
    if (typeof value === "string") {
      scrubbed[field] = withoutQuery(value)
    }
  })

  return { ...breadcrumb, data: scrubbed }
}

export function startErrorReporting(settings: ErrorReportingSettings) {
  init({
    dsn: settings.dsn,
    environment: settings.environment,
    release: settings.release ?? undefined,
    // Nothing about the person or their requests beyond the browser they use.
    dataCollection: {
      userInfo: false,
      cookies: false,
      httpHeaders: { request: { allow: ["User-Agent"] }, response: false },
      httpBodies: [],
      urlQueryParams: false,
      graphQL: { document: false, variables: false },
      genAI: { inputs: false, outputs: false },
      databaseQueryData: false,
      queues: false,
      stackFrameVariables: false,
    },
    integrations: keptIntegrations,
    beforeSend: scrubEvent,
    beforeBreadcrumb: scrubBreadcrumb,
  })
}
