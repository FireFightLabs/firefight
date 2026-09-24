import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { StepRow } from "@/pages/investigations/components/step-row"
import type { InvestigationStep } from "@/types/serializers"

interface StepsCardProps {
  steps: InvestigationStep[]
  className?: string
}

export function StepsCard({ steps, className }: StepsCardProps) {
  return (
    <Card className={className}>
      <CardHeader>
        <CardTitle>Steps</CardTitle>
        <CardDescription>
          Every tool it called, in order. The finding and the theories cite these numbers.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {steps.length === 0 ? (
          <p className="text-muted-foreground text-sm">No steps yet.</p>
        ) : (
          <ol className="divide-y">
            {steps.map((step) => (
              <StepRow key={step.position} step={step} />
            ))}
          </ol>
        )}
      </CardContent>
    </Card>
  )
}
