import { IconBulb, IconCircleCheck, IconCircleX, type Icon } from "@tabler/icons-react"

import { HYPOTHESIS_LABELS, isKeyOf, labelFor } from "@/components/investigations/labels"
import { StepLinks } from "@/components/investigations/step-links"
import { HYPOTHESIS_TONES, TONE_CLASSES } from "@/components/investigations/tone"
import type { HypothesisStatus } from "@/lib/generated/constants"
import type { InvestigationHypothesis } from "@/types/serializers"

const ICONS: Record<HypothesisStatus, Icon> = {
  open: IconBulb,
  supported: IconCircleCheck,
  refuted: IconCircleX,
}

function Theory({ hypothesis }: { hypothesis: InvestigationHypothesis }) {
  const status = isKeyOf(ICONS, hypothesis.status) ? hypothesis.status : null
  const StatusIcon = status ? ICONS[status] : IconBulb
  const tone = status ? HYPOTHESIS_TONES[status] : "neutral"

  return (
    <li className="flex gap-3">
      <span className={`mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full border ${TONE_CLASSES[tone]}`}>
        <StatusIcon className="size-3" strokeWidth={1.75} />
      </span>
      <div className="flex min-w-0 flex-col gap-1">
        <span className="text-[11px] font-medium tracking-[0.12em] text-muted-foreground uppercase">
          {labelFor(HYPOTHESIS_LABELS, hypothesis.status)}
          {hypothesis.confidence != null && ` · ${Math.round(hypothesis.confidence * 100)}% sure`}
        </span>
        <span className="text-sm leading-relaxed">{hypothesis.assertion}</span>
        <StepLinks steps={hypothesis.steps} />
      </div>
    </li>
  )
}

// Every theory it weighed, the one it kept and the ones it ruled out, each with the steps that decided it.
export function Theories({ hypotheses }: { hypotheses: InvestigationHypothesis[] }) {
  if (hypotheses.length === 0) {
    return <p className="text-sm text-muted-foreground">It did not write down any theories.</p>
  }

  return (
    <ul className="flex flex-col gap-4">
      {hypotheses.map((hypothesis) => (
        <Theory key={hypothesis.id} hypothesis={hypothesis} />
      ))}
    </ul>
  )
}
