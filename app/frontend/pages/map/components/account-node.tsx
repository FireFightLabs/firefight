import { IconWorldWww } from "@tabler/icons-react"
import type { Node, NodeProps } from "@xyflow/react"

import { ProviderMark } from "@/components/integrations/provider-mark"

export const ACCOUNT_NODE = "account"

export type AccountNodeData = {
  providerKey: string
  providerName: string
  providerMark?: string
  providerColor?: string
  account: string
  environment?: string
  count: number
  width: number
  height: number
}

export type AccountFlowNode = Node<AccountNodeData, typeof ACCOUNT_NODE>

// The box an account's resources sit in, headed by its provider, so several clouds read apart at a glance.
export function AccountNode({ data }: NodeProps<AccountFlowNode>) {
  return (
    <div
      className="rounded-2xl border border-border bg-surface-code/60"
      style={{ width: data.width, height: data.height }}
    >
      <div className="flex items-center gap-2 border-b border-border/40 px-3.5 py-2.5">
        {data.providerMark && data.providerColor ? (
          <ProviderMark providerKey={data.providerKey} mark={data.providerMark} color={data.providerColor} size={20} />
        ) : (
          <span className="flex size-5 items-center justify-center rounded-md bg-surface-selected text-fg-body">
            <IconWorldWww className="size-3.5" stroke={1.8} />
          </span>
        )}
        <span className="text-xs font-semibold text-foreground">{data.providerName}</span>
        <span className="truncate text-xs text-muted-foreground">{data.account}</span>
        {data.environment && (
          <span className="rounded-full border border-border/70 px-2 py-px text-[10.5px] text-muted-foreground">{data.environment}</span>
        )}
        <span className="ml-auto text-[10.5px] tabular-nums text-fg-muted">{data.count}</span>
      </div>
    </div>
  )
}
