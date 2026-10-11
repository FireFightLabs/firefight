import { useState } from "react"
import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"

export interface CreditPackOption {
  cents: number
  price: string
}

// What setup offers to buy with Firefight credits. Only Firefight's cloud sells them, so elsewhere there is none.
export interface CreditPurchase {
  packs: CreditPackOption[]
  markupPercent: number
  blockedReason: string | null
  checkoutPath: string
  starterNote: string | null
  starterEstimate: string | null
}

// The billing page's own words for what a call costs.
export function creditPriceNote(markupPercent: number) {
  return `Each call costs the model's list price plus ${markupPercent}%.`
}

// The packs Firefight's cloud sells, each opening its checkout. Where the checkout brings the buyer back to is in the
// path it posts to, so the same buttons serve the billing page and setup.
export function CreditPacks({ packs, blockedReason, checkoutPath }: { packs: CreditPackOption[]; blockedReason: string | null; checkoutPath: string }) {
  const [ buying, setBuying ] = useState<number | null>(null)

  function finishBuying() {
    setBuying(null)
  }

  function buy(pack: CreditPackOption) {
    setBuying(pack.cents)
    router.post(checkoutPath, { pack: pack.cents }, { preserveScroll: true, onFinish: finishBuying })
  }

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap items-center gap-2">
        {packs.map((pack) => (
          <Button
            key={pack.cents}
            variant="outline"
            size="sm"
            onClick={() => buy(pack)}
            disabled={Boolean(blockedReason) || buying !== null}
          >
            {buying === pack.cents ? "Opening…" : `Buy ${pack.price}`}
          </Button>
        ))}
      </div>
      <p className="text-xs text-muted-foreground">Packs are charged with tax added on top.</p>
      {blockedReason && <p className="text-sm text-muted-foreground">{blockedReason}</p>}
    </div>
  )
}
