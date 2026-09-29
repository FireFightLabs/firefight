import type { Node, NodeProps } from "@xyflow/react"

export type AccountNodeData = {
  label: string
  width: number
  height: number
}

export const ACCOUNT_NODE = "account"

export type AccountFlowNode = Node<AccountNodeData, typeof ACCOUNT_NODE>

// The box an account's resources sit in, so several clouds read apart at a glance.
export function AccountNode({ data }: NodeProps<AccountFlowNode>) {
  return (
    <div className="rounded-2xl border border-border/70 bg-muted/20" style={{ width: data.width, height: data.height }}>
      <div className="truncate px-4 pt-3 text-xs font-medium tracking-wide text-muted-foreground">{data.label}</div>
    </div>
  )
}
