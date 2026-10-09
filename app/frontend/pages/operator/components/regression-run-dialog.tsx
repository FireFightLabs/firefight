import { router } from "@inertiajs/react"
import { useState } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { OPERATOR_REGRESSION_MODELS_PROP } from "@/pages/operator/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { operatorHalonRegressionsPath } from "@/lib/routes"
import { useAction } from "@/pages/operator/hooks/use-action"
import type { OperatorHalonRegressionModel } from "@/types/serializers"

function answers(cases: number): string {
  return cases === 1 ? "rated answer" : `${cases} rated answers`
}

function investigations(cases: number): string {
  return cases === 1 ? "one investigation" : `${cases} investigations`
}

function loadModels() {
  router.reload({ only: [OPERATOR_REGRESSION_MODELS_PROP] })
}

// One id can be listed under several providers, so an option is named by both.
function modelKey(model: OperatorHalonRegressionModel): string {
  return `${model.provider}:${model.id}`
}

function modelOption(model: OperatorHalonRegressionModel): SearchableSelectOption {
  return { value: modelKey(model), label: `${model.name} (${model.provider})` }
}

export function RegressionRunDialog({
  open,
  onClose,
  cases,
  models,
}: {
  open: boolean
  onClose: () => void
  cases: number
  models?: OperatorHalonRegressionModel[]
}) {
  const [chosenKey, setChosenKey] = useState<string | null>(null)
  const { busy, post } = useAction()
  const chosen = (models ?? []).find((model) => modelKey(model) === chosenKey) ?? null

  function run() {
    post(operatorHalonRegressionsPath(), { model: chosen?.id ?? null, provider: chosen?.provider ?? null })
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Run the regression set</DialogTitle>
          <DialogDescription>
            Replays the latest {answers(cases)} on the model you choose. Each replay is a whole investigation on that model,
            so a run costs about what {investigations(cases)} would.
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-2">
          <Label htmlFor="regression-model">Model</Label>
          <SearchableSelect
            id="regression-model"
            value={chosenKey}
            onValueChange={setChosenKey}
            options={(models ?? []).map(modelOption)}
            placeholder="Halon's model"
            searchPlaceholder="Search models"
            emptyText={models ? "No model matches" : "Loading models"}
            onOpen={loadModels}
          />
          <p className="text-muted-foreground text-xs">Leave it on Halon&apos;s model to test the prompt as deployed.</p>
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="button" onClick={run} disabled={busy}>
            Run
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
