import { useCallback, useEffect, useMemo, useState } from "react"

import type { JsonObject } from "@/lib/tool-fields"
import { draftChanges, type FailureDraft, failureErrors, stepDraft, type StepDraft } from "@/pages/halon/lib/workflow/step-draft"
import type { WorkflowStepNode } from "@/types/serializers"

// A step's settings as they are being changed in the sheet, with the draft revision the person started from. While
// nothing is changed it follows the step as saved, so a change someone else made shows at once. Once something is
// changed it holds still, and sending it names the revision it started from, so the server refuses it if someone
// changed the same step since.
export function useStepDraft(step: WorkflowStepNode, revision: number | null) {
  const saved = useMemo(() => stepDraft(step), [ step ])
  const savedKey = JSON.stringify(saved)
  const [ draft, setDraft ] = useState<StepDraft>(saved)
  const [ baseRevision, setBaseRevision ] = useState(revision)
  const [ dirty, setDirty ] = useState(false)
  const [ configError, setConfigError ] = useState<string | null>(null)
  // Bumped whenever the draft is taken again from what is saved, so the editors start over from it.
  const [ generation, setGeneration ] = useState(0)

  useEffect(() => {
    if (dirty) {
      return
    }
    setDraft(JSON.parse(savedKey))
    setConfigError(null)
    setGeneration((count) => count + 1)
  }, [ savedKey, dirty ])

  useEffect(() => {
    if (!dirty) {
      setBaseRevision(revision)
    }
  }, [ revision, dirty ])

  const changeConfig = useCallback((config: JsonObject, error: string | null = null) => {
    setDraft((current) => ({ ...current, config }))
    setConfigError(error)
    setDirty(true)
  }, [])

  const changeFailure = useCallback((failure: FailureDraft) => {
    setDraft((current) => ({ ...current, failure }))
    setDirty(true)
  }, [])

  const reset = useCallback(() => {
    setDirty(false)
  }, [])

  const changes = useMemo(() => draftChanges(step, draft), [ step, draft ])
  const errors = useMemo(() => failureErrors(draft.failure, step.kind), [ draft.failure, step.kind ])
  const blocked = configError ?? Object.values(errors)[0] ?? null

  return { draft, baseRevision, dirty: dirty && Object.keys(changes).length > 0, changes, errors, blocked, generation, changeConfig, changeFailure, reset }
}
