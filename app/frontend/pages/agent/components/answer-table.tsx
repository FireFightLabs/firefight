import type { RenderedTag } from "@/pages/agent/types"

// Outside the plugin, so its margins and padding stay out of the frame. Inline code keeps the chip it has in prose.
const TABLE = [
  "w-full border-collapse text-left text-[13px] leading-normal text-ink tabular-nums",
  "[&_thead]:bg-inset [&_th]:border-b [&_th]:border-line [&_th]:px-3 [&_th]:py-2 [&_th]:text-[12px] [&_th]:font-medium [&_th]:text-ink-2",
  "[&_td]:border-b [&_td]:border-line [&_td]:px-3 [&_td]:py-2 [&_tbody_tr:last-child_td]:border-0",
  "[&_code]:rounded-[5px] [&_code]:bg-inset [&_code]:px-1 [&_code]:font-mono [&_code]:text-[0.9em] [&_strong]:font-semibold",
].join(" ")

export function AnswerTable({ node: _node, ...props }: RenderedTag<"table">) {
  return (
    <div className="not-prose my-3 overflow-x-auto rounded-card shadow-hairline">
      <table {...props} className={TABLE} />
    </div>
  )
}
