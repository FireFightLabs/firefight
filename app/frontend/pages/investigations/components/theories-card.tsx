import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { StepLinks } from "@/pages/investigations/components/step-links"
import { HYPOTHESIS_LABELS, labelFor } from "@/pages/investigations/lib/labels"
import type { InvestigationHypothesis } from "@/types/serializers"

export function TheoriesCard({ hypotheses }: { hypotheses: InvestigationHypothesis[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Theories</CardTitle>
        <CardDescription>What it thought might be going on, and what settled each.</CardDescription>
      </CardHeader>
      <CardContent>
        {hypotheses.length === 0 ? (
          <p className="text-muted-foreground text-sm">No theories recorded.</p>
        ) : (
          <ul className="flex flex-col gap-4">
            {hypotheses.map((hypothesis) => (
              <li key={hypothesis.id} className="flex flex-col gap-1.5">
                <Badge variant="outline" className="w-fit">
                  {labelFor(HYPOTHESIS_LABELS, hypothesis.status)}
                </Badge>
                <span className="text-sm">{hypothesis.assertion}</span>
                <StepLinks steps={hypothesis.steps} />
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
