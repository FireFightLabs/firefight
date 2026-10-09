import { Link } from "@inertiajs/react"
import { IconAlertTriangle, IconArrowRight } from "@tabler/icons-react"

import { formatDateTime } from "@/lib/formatters"
import { OPERATOR_PROCESS_TONES } from "@/lib/generated/constants"
import { since } from "@/pages/operator/lib/format"
import { processToneClasses } from "@/pages/operator/lib/tone"
import type { OperatorAttentionItem } from "@/types/serializers"

export function AttentionRow({ item }: { item: OperatorAttentionItem }) {
  const bad = item.tone === OPERATOR_PROCESS_TONES.BAD
  const open = (
    <>
      Open
      <IconArrowRight className="size-3.5" />
    </>
  )
  const openClass = "inline-flex items-center gap-1 rounded-md border border-border px-2.5 py-1 text-xs text-muted-foreground hover:text-foreground"

  return (
    <li className="grid grid-cols-[28px_minmax(0,1fr)_auto] items-start gap-4 border-b border-border px-5 py-3.5 last:border-b-0">
      <span className={`mt-0.5 flex size-7 items-center justify-center rounded-full border ${processToneClasses(item.tone)}`}>
        <IconAlertTriangle className="size-3.5" stroke={1.8} />
      </span>
      <div className="flex min-w-0 flex-col gap-0.5">
        <div className="flex flex-wrap items-baseline gap-x-3 gap-y-0.5">
          <span className={`text-sm font-medium ${bad ? "text-error" : ""}`}>{item.title}</span>
          <span className="truncate font-mono text-[13px]">{item.subject}</span>
          <span className="text-muted-foreground text-xs">{item.place}</span>
        </div>
        {item.detail && <p className="text-muted-foreground text-[13px]">{item.detail}</p>}
      </div>
      <div className="flex items-center gap-4">
        <time dateTime={item.at} title={formatDateTime(item.at)} className="text-muted-foreground font-mono text-xs">
          {since(item.at)}
        </time>
        {item.href && (item.external ? <a href={item.href} className={openClass}>{open}</a> : <Link href={item.href} className={openClass}>{open}</Link>)}
      </div>
    </li>
  )
}
