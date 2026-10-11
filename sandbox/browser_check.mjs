// Opens a page in a real browser the way a person would, on a desktop and a phone screen, and reports what they would
// meet: the status, how long it took, console errors, failed requests, the page's words and a screenshot. It can follow
// a short path of steps. Reading is free and sending is not. Every request that is not a GET, HEAD or OPTIONS is blocked
// here unless it belongs to the one step the person confirmed, so a path stops before it would send anything.
// The spec arrives on stdin, never in argv or on disk, since it may hold a saved login's password for this one run.
// Prints one JSON object on its last line.
import { createRequire } from "node:module"
import { existsSync } from "node:fs"
import dns from "node:dns/promises"
import http from "node:http"
import net from "node:net"

const MODULES = process.env.BROWSER_CHECK_MODULES || "/opt/browser/node_modules/"
const BROWSERS = "/opt/browser/ms-playwright"
// A terminal command is handed only the image's own settings, so the browsers' place is set here.
if (!process.env.PLAYWRIGHT_BROWSERS_PATH && existsSync(BROWSERS)) {
  process.env.PLAYWRIGHT_BROWSERS_PATH = BROWSERS
}
const require = createRequire(MODULES.endsWith("/") ? MODULES : `${MODULES}/`)
const { chromium, devices } = require("playwright")

const VIEWPORTS = {
  desktop: { viewport: { width: 1366, height: 900 } },
  phone: devices["Pixel 7"]
}
const READ_METHODS = new Set(["GET", "HEAD", "OPTIONS"])
const ACTIONS = new Set(["goto", "click", "fill", "press", "wait_for_text", "expect_text"])
const MAX_STEPS = 20
const MAX_PAGES = 30
const MAX_DEADLINE = 170
const ACTION_TIMEOUT = 10_000
const NAVIGATION_TIMEOUT = 30_000
const SETTLE = 2_000
const LIST_LIMIT = 50
const TEXT_LIMIT = 500
const PAGE_TEXT_LIMIT = 1_500
const PAGE_TEXT_QUIET = 600
const ERROR_TEXT_LIMIT = 600
const FIELD_LIMIT = 30
const FIELD_VALUE_LIMIT = 200
const HIDDEN = "[hidden]"
const SECRET_FIELD = /pass|token|secret|card|cvc|cvv|iban|ssn|otp|code|pin\b/i
const TWO_PART_SUFFIXES = new Set([
  "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "com.au", "net.au", "org.au", "co.nz", "org.nz", "co.jp", "ne.jp",
  "com.br", "com.cn", "com.hk", "co.in", "co.za", "com.mx", "com.tr", "co.kr", "com.sg", "com.ar", "co.il", "com.tw"
])

class Refused extends Error {}

// Private, loopback, link-local, shared, documentation and multicast ranges, which a check never reaches unless the
// install allowed them, since the box's network may reach inside.
const PRIVATE = new net.BlockList()
for (const [address, prefix] of [
  ["0.0.0.0", 8], ["10.0.0.0", 8], ["100.64.0.0", 10], ["127.0.0.0", 8], ["169.254.0.0", 16], ["172.16.0.0", 12],
  ["192.0.0.0", 24], ["192.0.2.0", 24], ["192.168.0.0", 16], ["198.18.0.0", 15], ["198.51.100.0", 24],
  ["203.0.113.0", 24], ["224.0.0.0", 4], ["240.0.0.0", 4]
]) PRIVATE.addSubnet(address, prefix, "ipv4")
for (const [address, prefix] of [
  ["::", 128], ["::1", 128], ["fc00::", 7], ["fe80::", 10], ["ff00::", 8], ["2001:db8::", 32], ["64:ff9b::", 96], ["100::", 64]
]) PRIVATE.addSubnet(address, prefix, "ipv6")

function privateAddress(address) {
  const mapped = address.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/i)
  if (mapped) return PRIVATE.check(mapped[1], "ipv4")
  return PRIVATE.check(address, net.isIPv6(address) ? "ipv6" : "ipv4")
}

function allowedPrivate(entries) {
  const names = new Set()
  const ranges = new net.BlockList()
  for (const entry of Array.isArray(entries) ? entries : []) {
    const text = String(entry).trim().toLowerCase()
    if (!text) continue
    const [address, prefix] = text.split("/")
    const family = net.isIP(address)
    if (family && prefix) ranges.addSubnet(address, Number(prefix), family === 6 ? "ipv6" : "ipv4")
    else if (family) ranges.addAddress(address, family === 6 ? "ipv6" : "ipv4")
    else names.add(text)
  }
  return { names, ranges }
}

function makeAddressCheck(allowed) {
  const cache = new Map()
  return async function check(host) {
    const name = host.replace(/^\[|\]$/g, "").toLowerCase()
    if (!cache.has(name)) cache.set(name, resolve(name))
    return cache.get(name)
  }

  async function resolve(name) {
    let addresses
    try {
      addresses = net.isIP(name) ? [{ address: name }] : await dns.lookup(name, { all: true })
    } catch {
      return { ok: false, reason: `${name} could not be found` }
    }
    if (addresses.length === 0) return { ok: false, reason: `${name} could not be found` }
    const named = allowed.names.has(name)
    for (const { address } of addresses) {
      if (!privateAddress(address) || named) continue
      const family = net.isIPv6(address) ? "ipv6" : "ipv4"
      if (!allowed.ranges.check(address, family)) return { ok: false, reason: `${name} is on a private network, which the browser does not reach` }
    }
    return { ok: true, address: addresses[0].address }
  }
}

// Every connection the browser makes goes through this proxy, redirects and sockets included, so an address is checked
// where it is reached and the name cannot point somewhere else between the check and the call.
function startProxy(check, refused) {
  const server = http.createServer(async (request, response) => {
    let target
    try {
      target = new URL(request.url)
    } catch {
      response.writeHead(400).end()
      return
    }
    const verdict = await check(target.hostname)
    if (!verdict.ok) {
      refused.push({ method: request.method, url: target.href, reason: verdict.reason })
      response.writeHead(403).end()
      return
    }
    const headers = { ...request.headers }
    delete headers["proxy-connection"]
    const upstream = http.request(
      { host: verdict.address, port: target.port || 80, method: request.method, path: `${target.pathname}${target.search}`, headers, setHost: false },
      (answer) => {
        response.writeHead(answer.statusCode, answer.headers)
        answer.pipe(response)
      }
    )
    upstream.on("error", () => response.destroy())
    request.pipe(upstream)
  })
  server.on("connect", async (request, socket, head) => {
    const [host, port] = splitHostPort(request.url)
    const verdict = await check(host)
    if (!verdict.ok) {
      refused.push({ method: "CONNECT", url: `https://${host}${port === "443" ? "" : `:${port}`}/`, reason: verdict.reason })
      socket.end("HTTP/1.1 403 Forbidden\r\n\r\n")
      return
    }
    const upstream = net.connect(Number(port), verdict.address, () => {
      socket.write("HTTP/1.1 200 Connection Established\r\n\r\n")
      if (head?.length) upstream.write(head)
      upstream.pipe(socket)
      socket.pipe(upstream)
    })
    upstream.on("error", () => socket.destroy())
    socket.on("error", () => upstream.destroy())
  })
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)))
}

function splitHostPort(value) {
  const match = String(value).match(/^\[?([^\]]+?)\]?:(\d+)$/)
  return match ? [match[1], match[2]] : [String(value), "443"]
}

function redact(value) {
  try {
    const url = new URL(value)
    if (!["http:", "https:"].includes(url.protocol)) return `${url.protocol}[redacted]`
    return `${url.origin}${url.pathname}${url.search ? "?[redacted]" : ""}${url.hash ? "#[redacted]" : ""}`
  } catch {
    return String(value).replace(/\?.*$/s, "?[redacted]")
  }
}

function siteOf(value) {
  let host
  try {
    host = new URL(value).hostname.toLowerCase()
  } catch {
    return null
  }
  if (net.isIP(host.replace(/^\[|\]$/g, ""))) return host
  const labels = host.split(".")
  const lastTwo = labels.slice(-2).join(".")
  return labels.slice(TWO_PART_SUFFIXES.has(lastTwo) ? -3 : -2).join(".")
}

const cut = (text, limit) => {
  const value = String(text ?? "").replace(/\s+/g, " ").trim()
  return value.length > limit ? `${value.slice(0, limit - 1)}…` : value
}

function fieldsOf(entries) {
  return entries.slice(0, FIELD_LIMIT).map(({ name, value, secret }) => ({
    name: cut(name, 100), value: secret || SECRET_FIELD.test(name) ? HIDDEN : cut(value, FIELD_VALUE_LIMIT)
  }))
}

function bodyFields(postData) {
  if (!postData) return []
  try {
    const parsed = JSON.parse(postData)
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return Object.entries(parsed).map(([name, value]) => ({ name, value: typeof value === "object" ? JSON.stringify(value) : String(value) }))
    }
  } catch {
    // Not JSON, so read it as a form.
  }
  try {
    return [...new URLSearchParams(postData)].map(([name, value]) => ({ name, value }))
  } catch {
    return []
  }
}

function validate(spec) {
  if (!spec || typeof spec !== "object") throw new Refused("The check needs a JSON object.")
  const start = new URL(String(spec.url ?? ""))
  if (!["http:", "https:"].includes(start.protocol)) throw new Refused("Only http and https addresses can be opened.")
  if (start.username || start.password) throw new Refused("An address with a user name or password in it cannot be opened.")
  const viewports = (Array.isArray(spec.viewports) && spec.viewports.length ? spec.viewports : ["desktop", "phone"]).map(String)
  for (const name of viewports) if (!VIEWPORTS[name]) throw new Refused(`There is no ${name} screen. Use desktop or phone.`)
  const steps = Array.isArray(spec.steps) ? spec.steps : []
  if (steps.length > MAX_STEPS) throw new Refused(`A path has at most ${MAX_STEPS} steps.`)
  steps.forEach((step, index) => {
    if (!ACTIONS.has(step?.action)) throw new Refused(`Step ${index + 1} has no action this browser knows.`)
    if (step.action === "goto") {
      const url = new URL(String(step.url ?? ""), start)
      if (!["http:", "https:"].includes(url.protocol)) throw new Refused(`Step ${index + 1} opens an address that is not http or https.`)
    }
  })
  const sendStep = Number.isInteger(spec.send_step) ? spec.send_step : null
  if (sendStep !== null && (sendStep < 1 || sendStep > steps.length)) throw new Refused("send_step names no step of the path.")
  return {
    url: start.href, viewports: sendStep === null ? [...new Set(viewports)] : [viewports[0]], steps, sendStep,
    expectedSend: spec.expected_send && spec.expected_send.method && spec.expected_send.url ? spec.expected_send : null,
    login: spec.login && spec.login.password ? spec.login : null,
    maxPages: Math.min(Math.max(Number(spec.max_pages) || 10, 1), MAX_PAGES),
    deadline: Date.now() + Math.min(Math.max(Number(spec.deadline_seconds) || 60, 5), MAX_DEADLINE) * 1000,
    privateHosts: spec.private_hosts, cutViewports: sendStep !== null && new Set(viewports).size > 1
  }
}

// A control is found by what a person reads on it. Buttons and links come before other text, and an exact match before
// a partial one, so "Track" clicks the button rather than a heading that starts with the same word.
async function locate(page, step) {
  const candidates = []
  if (step.role) candidates.push(page.getByRole(step.role, step.name ? { name: step.name, exact: true } : {}), page.getByRole(step.role, step.name ? { name: step.name } : {}))
  else if (step.label) candidates.push(page.getByLabel(step.label, { exact: true }), page.getByLabel(step.label))
  else if (step.placeholder) candidates.push(page.getByPlaceholder(step.placeholder, { exact: true }), page.getByPlaceholder(step.placeholder))
  else if (step.text) {
    for (const exact of [true, false]) {
      candidates.push(page.getByRole("button", { name: step.text, exact }), page.getByRole("link", { name: step.text, exact }),
        page.getByRole("menuitem", { name: step.text, exact }), page.getByRole("tab", { name: step.text, exact }), page.getByText(step.text, { exact }))
    }
  } else return null
  for (const candidate of candidates) {
    const visible = candidate.filter({ visible: true })
    if (await visible.count().catch(() => 0) > 0) return visible.first()
  }
  const wanted = step.role ? `${step.role} ${step.name || ""}` : step.label || step.placeholder || step.text
  throw new Refused(`Nothing on the page matches "${cut(wanted, 100)}".`)
}

// Whether acting on this element would submit a form that sends data, and what the form holds. A GET form, such as a
// search, is a navigation and runs.
async function submission(locator, action, key) {
  return locator.evaluate((element, [act, pressed]) => {
    let form = null
    let submitter = null
    if (act === "click") {
      const control = element.closest("button, input[type=submit], input[type=image]")
      if (control && control.form && (control.tagName !== "BUTTON" || (control.getAttribute("type") || "submit").toLowerCase() === "submit")) {
        form = control.form
        submitter = control
      }
    } else if (pressed === "Enter" && element.form && element.tagName === "INPUT") {
      form = element.form
    }
    if (!form) return null
    const method = ((submitter && submitter.getAttribute("formmethod")) || form.getAttribute("method") || "get").toLowerCase()
    if (method === "get" || method === "dialog") return null
    const passwords = new Set([...form.querySelectorAll("input[type=password]")].map((input) => input.name))
    let data
    try {
      data = new FormData(form, submitter || undefined)
    } catch {
      data = new FormData(form)
    }
    const fields = [...data.entries()].map(([name, value]) => ({
      name, value: typeof value === "string" ? value : "[file]", secret: passwords.has(name)
    }))
    return { method: method.toUpperCase(), url: (submitter && submitter.hasAttribute("formaction") ? submitter.formAction : form.action) || location.href, fields }
  }, [action, key])
}

async function visibleText(page, limit) {
  return cut(await page.evaluate(() => document.body?.innerText || "").catch(() => ""), limit)
}

async function errorText(page) {
  const said = await page.evaluate(() => {
    const seen = new Set()
    const nodes = [
      ...document.querySelectorAll("[role=alert], [aria-live=assertive], [class*=error i], [class*=invalid i]"),
      ...[...document.querySelectorAll("[aria-invalid=true]")].map((field) => field.closest("label, div, p, fieldset") || field)
    ]
    return nodes.filter((node) => {
      if (seen.has(node) || !node.offsetParent) return false
      seen.add(node)
      return true
    }).map((node) => node.innerText).filter((text) => text && text.trim()).join(" | ")
  }).catch(() => "")
  return cut(said, ERROR_TEXT_LIMIT)
}

async function timings(page) {
  return page.evaluate(() => {
    const entry = performance.getEntriesByType("navigation")[0]
    if (!entry) return null
    const ms = (value) => (value > 0 ? Math.round(value) : null)
    return {
      dns: ms(entry.domainLookupEnd - entry.domainLookupStart), connect: ms(entry.connectEnd - entry.connectStart),
      tls: entry.secureConnectionStart > 0 ? ms(entry.connectEnd - entry.secureConnectionStart) : null,
      first_byte: ms(entry.responseStart - entry.startTime), dom_content_loaded: ms(entry.domContentLoadedEventEnd - entry.startTime),
      load: ms(entry.loadEventEnd - entry.startTime)
    }
  }).catch(() => null)
}

async function screenshot(page) {
  const image = await page.screenshot({ type: "jpeg", quality: 70, scale: "css", timeout: ACTION_TIMEOUT }).catch(() => null)
  return image ? image.toString("base64") : null
}

async function runViewport(browser, name, run, proxyRefused) {
  const report = {
    name, width: null, height: null, status: null, final_url: null, title: null, timings_ms: null, console: [], failed_requests: [],
    blocked_requests: [], page_text: null, error_text: null, steps: [], stopped: null, pages: 0, login: null, screenshot: null,
    downloads_refused: 0, notes: []
  }
  const context = await browser.newContext({ ...VIEWPORTS[name], acceptDownloads: false, serviceWorkers: "block" })
  const page = await context.newPage()
  const size = page.viewportSize()
  report.width = size?.width ?? null
  report.height = size?.height ?? null
  const remaining = () => run.deadline - Date.now()
  page.setDefaultTimeout(ACTION_TIMEOUT)
  page.setDefaultNavigationTimeout(NAVIGATION_TIMEOUT)

  const state = { phase: "load", step: null, loginSite: null, sameSiteBlocked: null, changed: null, matched: false, pageCap: false, fileChooser: false }
  const aborted = new WeakSet()
  const check = run.check
  const pageSite = () => siteOf(page.url().startsWith("http") ? page.url() : run.url)
  const block = async (route, request, reason) => {
    aborted.add(request)
    if (report.blocked_requests.length < LIST_LIMIT) report.blocked_requests.push({ method: request.method(), url: redact(request.url()), reason })
    await route.abort("blockedbyclient").catch(() => {})
  }

  await context.route("**/*", async (route) => {
    const request = route.request()
    const url = request.url()
    let parsed
    try {
      parsed = new URL(url)
    } catch {
      return block(route, request, "not an address the browser opens")
    }
    if (["data:", "blob:"].includes(parsed.protocol)) return route.continue().catch(() => {})
    if (!["http:", "https:"].includes(parsed.protocol)) return block(route, request, "only http and https are opened")
    const verdict = await check(parsed.hostname)
    if (!verdict.ok) return block(route, request, verdict.reason)

    const method = request.method().toUpperCase()
    if (!READ_METHODS.has(method)) {
      const sameSite = siteOf(url) === pageSite()
      if (state.phase === "login") {
        if (siteOf(url) === state.loginSite) return route.continue().catch(() => {})
        return block(route, request, "the login only sends to its own site")
      }
      if (state.step !== null && state.step === run.sendStep && sameSite) {
        if (run.expectedSend && !state.matched) {
          const expected = new URL(run.expectedSend.url, run.url)
          const same = method === String(run.expectedSend.method).toUpperCase() && parsed.origin === expected.origin && parsed.pathname === expected.pathname
          if (!same) {
            state.changed ||= { method, url, postData: request.postData() }
            return block(route, request, "it is not what the person confirmed")
          }
          state.matched = true
        }
        return route.continue().catch(() => {})
      }
      if (sameSite && state.step !== null) state.sameSiteBlocked ||= { method, url, postData: request.postData() }
      return block(route, request, sameSite ? "it would send data, which needs the person's yes" : "a third party request that sends data")
    }

    let mainFrame = false
    try {
      mainFrame = request.isNavigationRequest() && request.frame() === page.mainFrame()
    } catch {
      mainFrame = false
    }
    if (mainFrame) {
      if (report.pages >= run.maxPages) {
        state.pageCap = true
        return block(route, request, `the run opens at most ${run.maxPages} pages`)
      }
      report.pages += 1
    }
    return route.continue().catch(() => {})
  })

  page.on("console", (message) => {
    const type = message.type()
    if (!["error", "warning"].includes(type) || report.console.length >= LIST_LIMIT) return
    const location = message.location()
    report.console.push({ type, text: cut(message.text(), TEXT_LIMIT), url: location?.url ? redact(location.url) : null })
  })
  page.on("pageerror", (error) => {
    if (report.console.length < LIST_LIMIT) report.console.push({ type: "pageerror", text: cut(error.message, TEXT_LIMIT), url: null })
  })
  page.on("requestfailed", (request) => {
    if (aborted.has(request) || report.failed_requests.length >= LIST_LIMIT) return
    if (proxyRefused.some((entry) => siteOf(entry.url) === siteOf(request.url()) || entry.url === request.url())) return
    report.failed_requests.push({ method: request.method(), url: redact(request.url()), status: null, error: request.failure()?.errorText ?? null })
  })
  page.on("response", (response) => {
    const request = response.request()
    try {
      if (request.isNavigationRequest() && request.frame() === page.mainFrame()) report.status = response.status()
    } catch {
      // A response from a frame that is gone says nothing about the page.
    }
    if (response.status() >= 400 && report.failed_requests.length < LIST_LIMIT) {
      report.failed_requests.push({ method: request.method(), url: redact(response.url()), status: response.status(), error: null })
    }
  })
  page.on("download", (download) => {
    report.downloads_refused += 1
    download.cancel().catch(() => {})
  })
  page.on("filechooser", () => {
    state.fileChooser = true
  })

  const open = async (target) => {
    try {
      await page.goto(target, { waitUntil: "load", timeout: Math.max(1_000, Math.min(NAVIGATION_TIMEOUT, remaining())) })
    } catch (error) {
      if (/Download is starting/i.test(error.message)) throw new Refused("That address is a download, and the browser does not download files.")
      throw error
    }
    await settle(page, remaining)
  }

  try {
    if (run.login) {
      report.login = await logIn(page, run.login, state, open, remaining)
      if (!report.login.ok) report.stopped = { step: 0, reason: "login_failed" }
    }
    if (!report.stopped) {
      state.phase = "load"
      await open(run.url)
      if (state.pageCap) report.stopped = { step: 0, reason: "page_cap" }
    }
    let before = null
    for (const [index, step] of run.steps.entries()) {
      if (report.stopped) break
      const n = index + 1
      if (remaining() <= 0) {
        report.stopped = { step: n, reason: "deadline" }
        break
      }
      state.phase = "steps"
      state.step = n
      state.sameSiteBlocked = null
      state.changed = null
      state.fileChooser = false
      const result = { n, action: step.action, ok: true, error: null, url_after: null }
      try {
        if (["click", "press"].includes(step.action)) {
          before = await screenshot(page)
          const target = await locate(page, step)
          if (step.action === "click" && !target) throw new Refused("Say what to click by its text, role and name, or label.")
          const submits = target ? await submission(target, step.action, step.key) : null
          if (submits && n !== run.sendStep) {
            result.ok = false
            result.error = "Not done. It would send the form."
            result.url_after = redact(page.url())
            report.steps.push(result)
            report.stopped = { step: n, reason: "sends_data", would_send: { method: submits.method, url: redact(submits.url), fields: fieldsOf(submits.fields) } }
            report.screenshot = before
            break
          }
        }
        await act(page, step, run, open, remaining)
        if (state.fileChooser) throw new Refused("The step opened a file picker, and the browser does not upload files.")
      } catch (error) {
        result.ok = false
        result.error = error instanceof Refused ? error.message : cut(error.message.split("\n")[0], TEXT_LIMIT)
      }
      if (state.pageCap) {
        result.error = `The run opens at most ${run.maxPages} pages.`
        report.stopped = { step: n, reason: "page_cap" }
      }
      result.url_after = page.url().startsWith("http") ? redact(page.url()) : null
      report.steps.push(result)
      if (state.changed) {
        const fields = bodyFields(state.changed.postData).map((field) => ({ ...field, secret: false }))
        report.stopped = { step: n, reason: "changed_request", would_send: { method: state.changed.method, url: redact(state.changed.url), fields: fieldsOf(fields) } }
        report.screenshot = before
        break
      }
      if (state.sameSiteBlocked && ["click", "press"].includes(step.action)) {
        const fields = bodyFields(state.sameSiteBlocked.postData).map((field) => ({ ...field, secret: false }))
        result.ok = false
        result.error ||= "Not done. It would send data."
        report.stopped = { step: n, reason: "sends_data", would_send: { method: state.sameSiteBlocked.method, url: redact(state.sameSiteBlocked.url), fields: fieldsOf(fields) } }
        report.screenshot = before
        break
      }
      if (report.stopped) break
      if (!result.ok) {
        report.stopped = { step: n, reason: "step_failed" }
        break
      }
    }
    if (run.sendStep !== null && !report.stopped && run.expectedSend && !state.matched) {
      report.notes.push("The confirmed step sent nothing, so nothing was changed.")
    }
  } catch (error) {
    if (!report.stopped) report.stopped = { step: state.step ?? 0, reason: remaining() <= 0 ? "deadline" : "step_failed" }
    report.notes.push(error instanceof Refused ? error.message : cut(error.message.split("\n")[0], TEXT_LIMIT))
  }

  state.step = null
  report.final_url = page.url().startsWith("http") ? redact(page.url()) : null
  report.title = cut(await page.title().catch(() => ""), 300) || null
  report.timings_ms = await timings(page)
  const troubled = report.stopped || (report.status ?? 0) >= 400 || report.failed_requests.length > 0 ||
    report.console.some((entry) => entry.type !== "warning")
  report.page_text = await visibleText(page, troubled ? PAGE_TEXT_LIMIT : PAGE_TEXT_QUIET)
  report.error_text = (await errorText(page)) || null
  report.screenshot ||= await screenshot(page)
  await context.close().catch(() => {})
  return report
}

async function settle(page, remaining) {
  await page.waitForLoadState("networkidle", { timeout: Math.max(100, Math.min(SETTLE, remaining())) }).catch(() => {})
}

async function act(page, step, run, open, remaining) {
  const timeout = Math.max(1_000, Math.min(ACTION_TIMEOUT, remaining()))
  switch (step.action) {
    case "goto":
      return open(new URL(String(step.url), page.url().startsWith("http") ? page.url() : run.url).href)
    case "click": {
      const target = await locate(page, step)
      if (!target) throw new Refused("Say what to click by its text, role and name, or label.")
      await target.click({ timeout })
      return settle(page, remaining)
    }
    case "fill": {
      const target = await locate(page, step)
      if (!target) throw new Refused("Say which field to fill by its label, placeholder, or role and name.")
      return target.fill(String(step.value ?? ""), { timeout })
    }
    case "press": {
      const target = await locate(page, step)
      if (target) await target.press(String(step.key || "Enter"), { timeout })
      else await page.keyboard.press(String(step.key || "Enter"))
      return settle(page, remaining)
    }
    case "wait_for_text":
      return page.getByText(String(step.text ?? "")).first().waitFor({ state: "visible", timeout })
    case "expect_text": {
      const shown = await page.getByText(String(step.text ?? "")).first().isVisible().catch(() => false)
      if (!shown) throw new Refused(`"${cut(step.text, 100)}" is not on the page.`)
      return null
    }
  }
}

async function logIn(page, login, state, open, remaining) {
  const start = login.login_url || login.site_url
  state.phase = "login"
  state.loginSite = siteOf(start)
  try {
    await open(start)
    const found = await page.evaluate(() => {
      const visible = (element) => element && element.offsetParent !== null
      const password = [...document.querySelectorAll("input[type=password]")].find(visible)
      if (!password) return { password: false }
      const scope = password.form || document
      const inputs = [...scope.querySelectorAll("input")].filter(visible)
      const named = /user|email|login/i
      const user = inputs.find((input) => input.type === "email") ||
        inputs.find((input) => input !== password && [input.name, input.id, input.autocomplete].some((value) => named.test(value || ""))) ||
        inputs.slice(0, inputs.indexOf(password)).reverse().find((input) => ["text", "email", "tel", ""].includes(input.type))
      password.setAttribute("data-firefight-login", "password")
      if (user) user.setAttribute("data-firefight-login", "user")
      const submit = password.form?.querySelector("button[type=submit], input[type=submit], button:not([type])")
      if (submit) submit.setAttribute("data-firefight-login", "submit")
      return { password: true, user: Boolean(user), submit: Boolean(submit) }
    })
    if (!found.password) return { ok: false, error: "No password field was found on the login page." }
    if (found.user) await page.fill("[data-firefight-login=user]", String(login.username ?? ""))
    await page.fill("[data-firefight-login=password]", String(login.password))
    const at = page.url()
    if (found.submit) await page.click("[data-firefight-login=submit]")
    else await page.press("[data-firefight-login=password]", "Enter")
    await page.waitForLoadState("load").catch(() => {})
    await settle(page, remaining)
    const stillAsked = page.url() === at && await page.locator("input[type=password]").first().isVisible().catch(() => false)
    if (stillAsked) {
      const said = await errorText(page)
      return { ok: false, error: `The login page is still showing after signing in${said ? `, and says: ${said}` : ""}.` }
    }
    return { ok: true, error: null }
  } catch (error) {
    return { ok: false, error: error instanceof Refused ? error.message : cut(error.message.split("\n")[0], TEXT_LIMIT) }
  } finally {
    state.phase = "load"
  }
}

// The password and username never leave the box in what this prints, wherever a page or an error echoed them.
function scrub(value, secrets) {
  if (typeof value === "string") {
    return secrets.reduce((text, secret) => text.split(secret).join("[hidden]"), value)
  }
  if (Array.isArray(value)) return value.map((each) => scrub(each, secrets))
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, each]) => [key, key === "screenshot" ? each : scrub(each, secrets)]))
  }
  return value
}

function secretsOf(login) {
  if (!login?.password) return []
  const password = String(login.password)
  return [...new Set([password, encodeURIComponent(password), JSON.stringify(password).slice(1, -1)])].filter((each) => each.length >= 3)
}

function print(answer, code) {
  process.stdout.write(`${JSON.stringify(answer)}\n`, () => process.exit(code))
}

async function readStdin() {
  const chunks = []
  for await (const chunk of process.stdin) chunks.push(chunk)
  return Buffer.concat(chunks).toString("utf8")
}

async function main() {
  let run
  let secrets = []
  try {
    const spec = JSON.parse(await readStdin())
    secrets = secretsOf(spec?.login)
    run = validate(spec)
  } catch (error) {
    return print(scrub({ error: error instanceof Refused || error instanceof TypeError ? error.message : "The check was not given a spec it can read." }, secrets), 2)
  }
  const proxyRefused = []
  run.check = makeAddressCheck(allowedPrivate(run.privateHosts))
  const answer = { viewports: [], error: null }
  // Whatever happens, an answer is printed before the app gives up on the command.
  const hardStop = setTimeout(() => {
    answer.error = "The run passed its time limit."
    print(scrub(answer, secrets), 0)
  }, Math.max(0, run.deadline - Date.now()) + 15_000)
  const proxy = await startProxy(run.check, proxyRefused)
  const browser = await chromium.launch({
    headless: true,
    args: ["--disable-extensions", "--disable-component-extensions-with-background-pages", "--no-first-run", "--disable-background-networking", "--disable-sync", "--disable-dev-shm-usage"],
    proxy: { server: `http://127.0.0.1:${proxy.address().port}`, bypass: "<-loopback>" }
  })
  try {
    const start = await run.check(new URL(run.url).hostname)
    if (!start.ok) {
      answer.error = `${start.reason}.`
    } else {
      for (const name of run.viewports) {
        const report = await runViewport(browser, name, run, proxyRefused)
        if (run.cutViewports) report.notes.push("A path that sends data runs on one screen only, so it is never sent twice.")
        answer.viewports.push(report)
      }
    }
    for (const refused of proxyRefused.slice(0, LIST_LIMIT)) {
      answer.viewports.at(-1)?.blocked_requests.push({ method: refused.method, url: redact(refused.url), reason: refused.reason })
    }
  } catch (error) {
    answer.error = cut(error.message.split("\n")[0], TEXT_LIMIT)
  } finally {
    await browser.close().catch(() => {})
    proxy.close()
    clearTimeout(hardStop)
  }
  print(scrub(answer, secrets), 0)
}

main()
