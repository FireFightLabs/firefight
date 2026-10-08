// Writes a provider's API endpoints as guides, read from the provider's own API client: every endpoint class it
// exports, with its method, path, purpose, permission, query options and body fields. Run by ProviderDocs::Package
// with Node's permission model, so the client it loads reads only its own folder.
//
//   node api_client_endpoints.mjs <install dir> <package> <out dir> <relative to> [parameter left out ...]
//
// Paths under <relative to> are written after it, as a tool that works inside that scope takes them. A parameter left
// out picks the path variant without it, such as the team scoped copy of every project path.
import { createRequire } from "node:module"
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import path from "node:path"

const [installDir, packageName, outDir, relativeTo, ...leftOut] = process.argv.slice(2)
const requireFrom = createRequire(path.join(installDir, "package.json"))
const client = requireFrom(packageName)
const manifestPath = requireFrom.resolve(`${packageName}/package.json`)
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"))
const typings = readFileSync(path.join(path.dirname(manifestPath), manifest.typings ?? manifest.types), "utf8").split("\n")

const MARK = "__"
const placeholders = new Proxy({}, {
  has: (_target, key) => !leftOut.includes(key),
  get: (_target, key) => (typeof key === "string" ? `${MARK}${key}${MARK}` : undefined),
})
const scopePrefix = relativeTo.replace(/\{(\w+)\}/g, `${MARK}$1${MARK}`)

// A type's shapes at one depth, from the client's typings, which put each member on its own line, indented four spaces
// a level. A type that is one of several shapes has an alternative for each. A required member that holds an object
// keeps its own shapes, so its required members are named too.
function alternativesOf(start, depth) {
  const indent = " ".repeat(depth * 4)
  const closing = `${" ".repeat((depth - 1) * 4)}}`
  const member = new RegExp(`^${indent}'([^']+)'(\\?)?: (.*)$`)
  const alternatives = [ [] ]
  for (let index = start; index < typings.length; index++) {
    const line = typings[index]
    if (line === `${closing} | {`) {
      alternatives.push([])
      continue
    }
    if (line.startsWith(closing)) {
      break
    }
    const found = line.match(member)
    if (!found) {
      continue
    }
    const [, name, optional, type] = found
    const opens = type.endsWith("{")
    const nested = opens && !optional ? alternativesOf(index + 1, depth + 1) : [ [] ]
    alternatives.at(-1).push({ name: opens && closesAsArray(index + 1, indent) ? `${name}[]` : name, required: !optional, nested })
  }
  return alternatives
}

// Whether a member that opens an object closes as an array of them.
function closesAsArray(start, indent) {
  const line = typings.slice(start).find((each) => each.startsWith(`${indent}}`) && each !== `${indent}} | {`)
  return Boolean(line?.trim().startsWith("}[]"))
}

// The required members of one shape, a nested one written with dots. A member that is one of several shapes is written
// with each shape's required members in braces, such as build {dockerfile.path} or {buildpack}.
function requiredOf(members, prefix = "") {
  return members.filter((member) => member.required).flatMap((member) => {
    const name = `${prefix}${member.name}`
    const shapes = oneOf(member.nested.map((shape) => requiredOf(shape)))
    if (shapes.length > 1) {
      return [ `${name} ${shapes.map((shape) => `{${shape.join(", ")}}`).join(" or ")}` ]
    }
    return shapes[0].length > 0 ? shapes[0].map((inner) => `${name}.${inner}`) : [ name ]
  })
}

// Shapes that require the same members are one shape to whoever writes the body.
function oneOf(shapes) {
  const seen = new Set()
  return shapes.filter((shape) => !seen.has(shape.join()) && seen.add(shape.join()))
}

function typeStart(name) {
  const index = typings.findIndex((line) => line.startsWith(`type ${name} = {`))
  return index === -1 ? null : index + 1
}

function fieldsOf(name) {
  const start = typeStart(name)
  if (start === null) {
    return null
  }
  const shapes = alternativesOf(start, 1)
  const required = oneOf(shapes.map((shape) => requiredOf(shape)))
  const requiredNames = new Set(shapes.flat().filter((member) => member.required).map((member) => member.name))
  const optional = [ ...new Set(shapes.flat().filter((member) => !member.required && !requiredNames.has(member.name)).map((member) => member.name)) ]
  return {
    required: required.length > 1 ? [ `one of ${required.map((shape) => `{${shape.join(", ")}}`).join(" or ")}` ] : required[0],
    optional,
  }
}

function deprecationOf(className) {
  const index = typings.findIndex((line) => line.startsWith(`declare class ${className} `))
  for (let line = index - 1; line >= 0 && !typings[line].startsWith("/**"); line--) {
    const found = typings[line].match(/@deprecated (.*)$/)
    if (found) {
      return found[1].trim()
    }
  }
  return null
}

function sentence(text) {
  const trimmed = text.trim()
  return /[.!?]$/.test(trimmed) ? trimmed : `${trimmed}.`
}

const endpoints = Object.keys(client).filter((name) => name.endsWith("Endpoint")).flatMap((className) => {
  let endpoint
  try {
    endpoint = new client[className]({})
  } catch {
    return []
  }
  if (typeof endpoint.endpointUrl !== "function" || !endpoint.description) {
    return []
  }
  const url = endpoint.endpointUrl({ parameters: placeholders, options: {} })
  const inScope = url.startsWith(scopePrefix)
  const written = (inScope ? url.slice(scopePrefix.length) : url).replace(new RegExp(`${MARK}(\\w+)${MARK}`, "g"), "{$1}")
  const base = className.replace(/Endpoint$/, "")
  return [ {
    method: endpoint.method,
    path: written,
    inScope,
    area: (inScope ? written : written.replace(/^\/v\d+\//, "")).split("/")[0],
    description: sentence(endpoint.description),
    permission: endpoint.requiredPermissions || null,
    deprecated: deprecationOf(className),
    query: fieldsOf(`${base}Options`),
    body: fieldsOf(`${base}Data`),
  } ]
})

// A client whose shape changed, or a scope that names nothing, fails the run rather than writing an empty list.
if (endpoints.length === 0 || !endpoints.some((endpoint) => endpoint.inScope)) {
  process.stderr.write(`${packageName} defines no endpoints under ${relativeTo}\n`)
  process.exit(1)
}

const METHOD_ORDER = [ "GET", "POST", "PUT", "PATCH", "DELETE" ]
endpoints.sort((left, right) => left.path.localeCompare(right.path) || METHOD_ORDER.indexOf(left.method) - METHOD_ORDER.indexOf(right.method))

function detail(endpoint) {
  const lines = [ `### ${endpoint.method} ${endpoint.path}`, "", endpoint.description ]
  if (endpoint.body) {
    const { required, optional } = endpoint.body
    if (required.length > 0) {
      lines.push(`Body, required: ${required.join(", ")}.`)
    }
    if (optional.length > 0) {
      lines.push(`Body, optional: ${optional.join(", ")}.`)
    }
  }
  if (endpoint.query && endpoint.query.optional.length + endpoint.query.required.length > 0) {
    lines.push(`Query: ${[ ...endpoint.query.required, ...endpoint.query.optional ].join(", ")}.`)
  }
  if (endpoint.permission) {
    lines.push(`Permission: ${endpoint.permission}.`)
  }
  if (endpoint.deprecated) {
    lines.push(`Deprecated: ${sentence(endpoint.deprecated)}`)
  }
  return lines.join("\n")
}

const origin = `${packageName} ${manifest.version}`
const scopes = [
  { inScope: true, folder: "project", heading: `Paths written after ${relativeTo}` },
  { inScope: false, folder: "outside", heading: `Paths outside ${relativeTo}, written in full` },
]

const index = [
  "# API endpoints",
  "",
  `Every endpoint in the provider's API, as its own API client (${origin}) defines them, with the method and path. ` +
    "An operation that is not listed here is not in the API, so it cannot be done through it.",
  "",
  `Paths inside ${relativeTo} are written after it. The rest are written in full. Each area's file, named under it, ` +
    "gives each endpoint's purpose, the body fields it requires and takes, its query options and the permission it needs.",
]

for (const scope of scopes) {
  const inScope = endpoints.filter((endpoint) => endpoint.inScope === scope.inScope)
  const areas = [ ...new Set(inScope.map((endpoint) => endpoint.area)) ].sort()
  index.push("", `## ${scope.heading}`)
  for (const area of areas) {
    const inArea = inScope.filter((endpoint) => endpoint.area === area)
    const file = `${scope.folder}/${area}.md`
    index.push("", `### ${area} (${file})`, "", ...inArea.map((endpoint) => `- ${endpoint.method} ${endpoint.path}`))
    const page = [ `# ${area}`, "", `${scope.heading}. Every endpoint here is from ${origin}.`, "", ...inArea.map(detail).join("\n\n").split("\n") ]
    mkdirSync(path.join(outDir, scope.folder), { recursive: true })
    writeFileSync(path.join(outDir, file), `${page.join("\n")}\n`)
  }
}

writeFileSync(path.join(outDir, "index.md"), `${index.join("\n")}\n`)
process.stdout.write(`${endpoints.length} endpoints from ${origin}\n`)
