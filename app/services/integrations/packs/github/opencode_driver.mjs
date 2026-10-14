#!/usr/bin/env node
// Runs OpenCode for a code fix as `opencode run --format json` does at 1.18.34 (packages/opencode/src/cli/cmd/run.ts),
// printing the same events, except that a permission OpenCode asks about goes to Firefight to decide rather than being
// refused. It starts `opencode serve` on the box's own loopback with a password of its own, opens or resumes the
// session, sends the brief, and mirrors the session's events until it is idle. A permission asked is put to Firefight
// with the agent's latest events, asked again while Firefight says to wait, and answered with Firefight's reply.
//
// Arguments: the brief, the model as provider/model, the session to resume or nothing, and Firefight's address for
// permissions. The session's token is the one the config hands Firefight's tools server.
import { spawn } from "node:child_process"
import { readFileSync } from "node:fs"
import { createServer } from "node:net"
import { randomBytes } from "node:crypto"

const [message, model, resume, askUrl] = process.argv.slice(2)
const RECENT = 20
const STARTUP_MS = 30_000
const ANSWER_MS = 30_000
const RETRY_MS = 2_000
const RETRIES = 15
const RUN_RULES = ["question", "plan_enter", "plan_exit"].map((permission) => ({ permission, action: "deny", pattern: "*" }))

const config = JSON.parse(readFileSync(process.env.OPENCODE_CONFIG, "utf8"))
const tokenHeader = Object.values(config.mcp ?? {}).map((server) => server.headers?.Authorization).find(Boolean)
const password = randomBytes(24).toString("hex")
const auth = `Basic ${Buffer.from(`opencode:${password}`).toString("base64")}`
const recent = []
let sessionID
let failed = false
let finished = false

function emit(type, data) {
  const line = JSON.stringify({ type, timestamp: Date.now(), sessionID, ...data })
  process.stdout.write(line + "\n")
  if (type !== "permission_wait") {
    recent.push(line)
    if (recent.length > RECENT) {
      recent.shift()
    }
  }
}

function freePort() {
  return new Promise((resolve, reject) => {
    const probe = createServer()
    probe.once("error", reject)
    probe.listen(0, "127.0.0.1", () => {
      const { port } = probe.address()
      probe.close(() => resolve(port))
    })
  })
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

// The run ends with why in plain words, as an error event the app reads the stop reason from.
function stop(words) {
  failed = true
  emit("error", { error: { name: "DriverError", data: { message: words } } })
}

const port = await freePort()
const server = spawn("opencode", ["serve", "--hostname", "127.0.0.1", "--port", String(port)], {
  env: { ...process.env, OPENCODE_SERVER_PASSWORD: password },
  stdio: ["ignore", "pipe", "inherit"],
})
// What the server says goes to the error output, since the standard output carries only the session's events.
server.stdout.pipe(process.stderr)
server.on("exit", (code) => {
  if (!finished) {
    stop(`OpenCode stopped unexpectedly with exit code ${code}`)
    process.exit(1)
  }
})

// The server listens before it attaches its handler, and a connection accepted in between is never answered
// (NodeHttpServer under Server.listen at 1.18.34). So nothing is sent until it says it is listening, which is what
// OpenCode's own SDK waits for (createOpencodeServer in packages/sdk/js/src/server.ts).
const base = await new Promise((resolve) => {
  const deadline = setTimeout(() => {
    stop(`OpenCode did not start within ${STARTUP_MS / 1000} seconds`)
    server.kill("SIGKILL")
    process.exit(1)
  }, STARTUP_MS)
  let said = ""
  const listen = (chunk) => {
    said += chunk.toString()
    const listening = said.match(/^opencode server listening on (https?:\/\/\S+)/m)
    if (listening) {
      clearTimeout(deadline)
      server.stdout.off("data", listen)
      resolve(listening[1])
    }
  }
  server.stdout.on("data", listen)
})

function unreachable(error) {
  if (error.name === "TimeoutError" || error.name === "AbortError") {
    return `OpenCode did not answer within ${ANSWER_MS / 1000} seconds`
  }
  return `OpenCode could not be reached (${error.cause?.code ?? error.message})`
}

// Every call but the event stream is answered at once, so one that is not means OpenCode hangs and the run ends now.
async function api(method, path, body) {
  let response
  try {
    response = await fetch(base + path, {
      method,
      headers: { Authorization: auth, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(ANSWER_MS),
    })
  } catch (error) {
    throw new Error(unreachable(error))
  }
  if (!response.ok) {
    throw new Error(`OpenCode refused ${method} ${path} with status ${response.status}`)
  }
  const text = await response.text()
  return text ? JSON.parse(text) : undefined
}

// Firefight decides, and says to wait until it has. A Firefight that cannot be reached, or fails to answer again and
// again, refuses the step, since nothing else may answer it.
function ask(asked, extra = {}) {
  return fetch(askUrl, {
    method: "POST",
    headers: { Authorization: tokenHeader, "Content-Type": "application/json" },
    body: JSON.stringify({
      id: asked.id,
      sessionID: asked.sessionID,
      permission: asked.permission,
      patterns: asked.patterns,
      metadata: asked.metadata,
      events: recent,
      ...extra,
    }),
  })
}

async function decide(asked) {
  let failures = 0
  for (;;) {
    let answer
    try {
      const response = await ask(asked)
      if (response.status === 401) {
        return { reply: "reject", message: "The change ended before this step was decided." }
      }
      answer = response.ok ? await response.json() : undefined
    } catch {
      answer = undefined
    }
    if (answer?.reply) {
      return answer
    }
    emit("permission_wait", { permission: asked.permission })
    if (answer) {
      failures = 0
    } else {
      failures += 1
      if (failures >= RETRIES) {
        return { reply: "reject", message: "Firefight could not decide this step, so it was refused." }
      }
      await sleep(RETRY_MS)
    }
  }
}

// Everything in the box runs as one user, so the agent can reach this server too. Only the driver's own reply is
// trusted: a reply it did not send, or its own finding the request already answered, means something else answered
// OpenCode. Firefight is told, which stops the run and opens nothing, and the session is stopped here as well.
const asked = new Map()
const ours = new Set()
const reported = new Set()
let stopping = false

async function answerPermission(question) {
  asked.set(question.id, question)
  const answer = await decide(question)
  if (reported.has(question.id)) {
    return
  }
  ours.add(question.id)
  try {
    await api("POST", `/permission/${question.id}/reply`, { reply: answer.reply, message: answer.message })
  } catch {
    await answeredInBox(question)
  }
}

async function answeredInBox(question) {
  if (reported.has(question.id)) {
    return
  }
  reported.add(question.id)
  let message = "The coding agent answered its own question about a step instead of waiting for Halon, so it was stopped."
  try {
    const answer = await (await ask(question, { answeredInBox: true })).json()
    message = answer.message ?? message
  } catch {
    // The run stops whether or not Firefight heard, and Firefight refuses the agent's next model call either way.
  }
  failed = true
  stopping = true
  emit("error", { error: { name: "AnsweredInBox", data: { message } } })
  await api("POST", `/session/${sessionID}/abort`).catch(() => {})
}

// The stream stays open for the whole run, so only its answer is timed, not its end.
async function mirror(sessions) {
  const opening = new AbortController()
  const unanswered = setTimeout(() => opening.abort(), ANSWER_MS)
  let response
  try {
    response = await fetch(base + "/event", { headers: { Authorization: auth, Accept: "text/event-stream" }, signal: opening.signal })
  } catch (error) {
    throw new Error(unreachable(error))
  } finally {
    clearTimeout(unanswered)
  }
  if (!response.ok) {
    throw new Error(`OpenCode refused GET /event with status ${response.status}`)
  }
  const decoder = new TextDecoder()
  let buffered = ""
  const reader = response.body.getReader()
  return {
    async *events() {
      for (;;) {
        const { value, done } = await reader.read()
        if (done) {
          return
        }
        buffered += decoder.decode(value, { stream: true })
        let end
        while ((end = buffered.indexOf("\n\n")) >= 0) {
          const block = buffered.slice(0, end)
          buffered = buffered.slice(end + 2)
          const data = block
            .split("\n")
            .filter((line) => line.startsWith("data:"))
            .map((line) => line.slice(5).trimStart())
            .join("\n")
          if (data) {
            yield JSON.parse(data)
          }
        }
      }
    },
    sessions,
  }
}

async function main() {
  const stream = await mirror(new Set())
  sessionID = resume || (await api("POST", "/session", { permission: RUN_RULES })).id
  stream.sessions.add(sessionID)
  const [providerID, ...rest] = model.split("/")
  await api("POST", `/session/${sessionID}/prompt_async`, {
    model: { providerID, modelID: rest.join("/") },
    parts: [{ type: "text", text: message }],
  })

  for await (const event of stream.events()) {
    const properties = event.properties ?? {}
    if (event.type === "session.created" && stream.sessions.has(properties.info?.parentID)) {
      stream.sessions.add(properties.info.id)
    }
    if (event.type === "message.part.updated") {
      const part = properties.part
      if (part.sessionID !== sessionID) {
        continue
      }
      if (part.type === "tool" && (part.state.status === "completed" || part.state.status === "error")) {
        emit("tool_use", { part })
      } else if (part.type === "step-start") {
        emit("step_start", { part })
      } else if (part.type === "step-finish") {
        emit("step_finish", { part })
      } else if (part.type === "text" && part.time?.end) {
        emit("text", { part })
      }
    }
    if (event.type === "session.error" && properties.sessionID === sessionID && properties.error) {
      failed = true
      emit("error", { error: properties.error })
    }
    if (event.type === "permission.asked" && stream.sessions.has(properties.sessionID)) {
      answerPermission(properties)
    }
    if (event.type === "permission.replied" && stream.sessions.has(properties.sessionID) && !ours.has(properties.requestID)) {
      await answeredInBox(asked.get(properties.requestID) ?? { id: properties.requestID, sessionID: properties.sessionID, permission: "unknown" })
    }
    if (stopping || (event.type === "session.status" && properties.sessionID === sessionID && properties.status?.type === "idle")) {
      break
    }
  }
}

try {
  await main()
} catch (error) {
  stop(error.message)
}
finished = true
server.kill()
process.exit(failed ? 1 : 0)
