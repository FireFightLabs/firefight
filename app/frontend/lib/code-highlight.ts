import type { LanguageFn } from "highlight.js"
import hljs from "highlight.js/lib/core"

// Every language highlight.js knows, each its own chunk, fetched the first time a block in that language shows.
const LANGUAGE_FILES = import.meta.glob<{ default: LanguageFn }>([
  "../../../node_modules/highlight.js/es/languages/*.js",
  "!../../../node_modules/highlight.js/es/languages/*.js.js",
])

const FILE_BY_NAME = new Map(
  Object.entries(LANGUAGE_FILES).map(([ path, load ]) => [ path.split("/").pop()?.replace(/\.js$/, "") ?? "", load ]),
)

// Names people write on a fence that are not a language file's own name. Any other alias a language declares works
// once that language has loaded.
const ALIASES: Record<string, string> = {
  rb: "ruby", erb: "erb", ts: "typescript", tsx: "typescript", js: "javascript", jsx: "javascript", mjs: "javascript", cjs: "javascript",
  yml: "yaml", sh: "bash", shell: "bash", zsh: "bash", console: "bash", shellsession: "bash", py: "python", golang: "go", rs: "rust",
  kt: "kotlin", cs: "csharp", "c#": "csharp", "c++": "cpp", html: "xml", svg: "xml", vue: "xml", md: "markdown", tf: "ini", hcl: "ini",
  toml: "ini", jsonc: "json", json5: "json", psql: "pgsql", postgres: "pgsql", postgresql: "pgsql", docker: "dockerfile", ps1: "powershell",
  ex: "elixir", exs: "elixir", proto: "protobuf", gql: "graphql", text: "plaintext", txt: "plaintext", plain: "plaintext",
}

// What a block without a language is most likely to be, guessed among these only, so a guess loads a few files at most.
const GUESSED = [ "bash", "ruby", "typescript", "javascript", "python", "go", "yaml", "json", "sql", "dockerfile", "xml", "css", "ini" ]
// Below this highlight.js is guessing, and plain text reads better than wrong colours.
const SURE_ENOUGH = 7

const loading = new Map<string, Promise<boolean>>()

function fileFor(language: string): string | undefined {
  const name = language.trim().toLowerCase()
  const resolved = ALIASES[name] ?? name
  return FILE_BY_NAME.has(resolved) ? resolved : undefined
}

function load(name: string): Promise<boolean> {
  const started = loading.get(name)
  if (started) {
    return started
  }
  const file = FILE_BY_NAME.get(name)
  const loaded = file
    ? file().then((module) => {
      hljs.registerLanguage(name, module.default)
      return true
    }).catch(() => false)
    : Promise.resolve(false)
  loading.set(name, loaded)
  return loaded
}

// The block as HTML highlight.js wrote, which escapes the code itself, or null for plain text: a language it does not
// know, one that failed to load, or a guess it is not sure of.
export async function highlight(code: string, language: string | undefined): Promise<string | null> {
  if (language) {
    const known = hljs.getLanguage(language) ? language : fileFor(language)
    if (!known || known === "plaintext" || !(hljs.getLanguage(known) || await load(known))) {
      return null
    }
    return hljs.highlight(code, { language: known, ignoreIllegals: true }).value
  }

  const ready = (await Promise.all(GUESSED.map(async (name) => ((await load(name)) ? name : null)))).filter((name) => name !== null)
  const guessed = hljs.highlightAuto(code, ready)
  return guessed.relevance >= SURE_ENOUGH ? guessed.value : null
}

// The language a fenced block names, from react-markdown's "language-ruby" class.
export function fenceLanguage(className: string | undefined): string | undefined {
  return className?.split(" ").find((name) => name.startsWith("language-"))?.slice("language-".length) || undefined
}
