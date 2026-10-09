import { newTabAttributes } from "@/lib/links"
import type { RenderedTag } from "@/pages/agent/types"

export function AnswerLink({ node: _node, ...props }: RenderedTag<"a">) {
  return <a {...props} {...newTabAttributes(props.href)} />
}
