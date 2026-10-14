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
const STARTUP_MS = 60_000
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

const port = await freePort()
const base = `http://127.0.0.1:${port}`
const server = spawn("opencode", ["serve", "--hostname", "127.0.0.1", "--port", String(port)], {
  env: { ...process.env, OPENCODE_SERVER_PASSWORD: password },
  stdio: ["ignore", "ignore", "inherit"],
})
server.on("exit", (code) => {
  if (!finished) {
    process.stderr.write(`opencode serve exited with ${code}\n`)
    process.exit(1)
  }
})

async function api(method, path, body) {
  const response = await fetch(base + path, {
    method,
    headers: { Authorization: auth, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  if (!response.ok) {
    throw new Error(`${method} ${path} answered ${response.status}: ${await response.text()}`)
  }
  const text = await response.text()
  return text ? JSON.parse(text) : undefined
}

async function ready() {
  const deadline = Date.now() + STARTUP_MS
  while (Date.now() < deadline) {
    try {
      await api("GET", "/session/status")
      return
    } catch {
      await sleep(250)
    }
  }
  throw new Error("opencode serve did not start")
}

// Firefight decides, and says to wait until it has. A Firefight that cannot be reached, or fails to answer again and
// again, refuses the step, since nothing else may answer it.
async function decide(asked) {
  let failures = 0
  for (;;) {
    let answer
    try {
      const response = await fetch(askUrl, {
        method: "POST",
        headers: { Authorization: tokenHeader, "Content-Type": "application/json" },
        body: JSON.stringify({ id: asked.id, permission: asked.permission, patterns: asked.patterns, metadata: asked.metadata, events: recent }),
      })
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

async function answerPermission(asked) {
  const answer = await decide(asked)
  await api("POST", `/permission/${asked.id}/reply`, { reply: answer.reply, message: answer.message }).catch((error) =>
    process.stderr.write(`${error.message}\n`),
  )
}

async function mirror(sessions) {
  const response = await fetch(base + "/event", { headers: { Authorization: auth, Accept: "text/event-stream" } })
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
  await ready()
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
    if (event.type === "session.status" && properties.sessionID === sessionID && properties.status?.type === "idle") {
      break
    }
  }
}

try {
  await main()
} catch (error) {
  failed = true
  process.stderr.write(`${error.message}\n`)
}
finished = true
server.kill()
process.exit(failed ? 1 : 0)
