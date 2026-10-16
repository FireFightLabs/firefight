import { written } from "@/lib/tool-fields"

// A step's tool, as its tool's name with the arguments below it.
export function stepCall(tool: string, args: Record<string, unknown>): string {
  const lines = Object.entries(args).map(([ key, value ]) => `${key}: ${written(value)}`)
  return [ tool, ...lines ].join("\n")
}
