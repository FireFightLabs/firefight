import type { HttpResponse } from "@inertiajs/core"

export function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
}

// The body parses to null when unparsable. Network failures still throw so
// callers decide how to degrade.
type JsonRequestInit = Omit<RequestInit, "body"> & { body?: unknown }

export async function requestJson<T>(
  path: string,
  { method = "POST", body, ...init }: JsonRequestInit = {}
): Promise<{ ok: boolean; status: number; data: T | null }> {
  const response = await fetch(path, {
    method,
    ...init,
    headers: {
      "X-CSRF-Token": csrfToken(),
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      ...init.headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  const data = (await response.json().catch(() => null)) as T | null
  return { ok: response.ok, status: response.status, data }
}

export function postJson<T>(path: string, body?: unknown, init: Omit<JsonRequestInit, "body" | "method"> = {}) {
  return requestJson<T>(path, { ...init, method: "POST", body })
}

export const TOO_MANY_STATUS = 429

const HOUR_SECONDS = 3600

// "in an hour" or "in a minute", from the Retry-After a throttled answer carries, so the page never restates the throttle.
export function retryWait(response: HttpResponse): string {
  const seconds = Number(response.headers["retry-after"])
  if (!seconds) {
    return "later"
  }
  return seconds >= HOUR_SECONDS ? "in an hour" : "in a minute"
}
