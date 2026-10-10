import { IconChevronRight, IconLoader2 } from "@tabler/icons-react"
import { useEffect, useState } from "react"

import { HELPER_STATUSES } from "@/lib/generated/constants"
import type { HelperGroup } from "@/components/investigations/story"
import { StoryEntryRow } from "@/components/investigations/story-entry-row"
import type { InvestigationDetail, InvestigationHelper } from "@/types/serializers"

const STATUS_WORDS: Record<InvestigationHelper["status"], string> = {
  [HELPER_STATUSES.RUNNING]: "Checking",
  [HELPER_STATUSES.REPORTED]: "Reported",
  [HELPER_STATUSES.FAILED]: "No report",
  [HELPER_STATUSES.STOPPED]: "Stopped",
}

interface HelperGroupsProps {
  groups: HelperGroup[]
  investigation: InvestigationDetail
}

// The helpers one call handed checks to, each folded to its name, its step numbers and what it reported, and opened to
// the steps it took.
export function HelperGroups({ groups, investigation }: HelperGroupsProps) {
  return (
    <ul className="flex flex-col gap-3">
      {groups.map((group) => (
        <HelperGroupRow key={group.helper.id} group={group} investigation={investigation} />
      ))}
    </ul>
  )
}

function HelperGroupRow({ group, investigation }: { group: HelperGroup; investigation: InvestigationDetail }) {
  const { helper, steps } = group
  const running = helper.status === HELPER_STATUSES.RUNNING
  const positions = steps.map((step) => step.position)
  const held = positions.map((position) => `#step-${position}`).join(" ")
  const [ open, setOpen ] = useState(false)
  const said = helper.report ?? helper.endedBecause

  // A citation links to a step by its number, so a helper holding that step opens to show it.
  useEffect(() => {
    function openWhenCited() {
      if (window.location.hash !== "" && held.split(" ").includes(window.location.hash)) {
        setOpen(true)
      }
    }

    openWhenCited()
    window.addEventListener("hashchange", openWhenCited)
    return () => window.removeEventListener("hashchange", openWhenCited)
  }, [ held ])

  function toggle() {
    setOpen(!open)
  }

  return (
    <li className="flex min-w-0 flex-col gap-1">
      <button
        type="button"
        onClick={toggle}
        aria-expanded={open}
        disabled={steps.length === 0}
        className="inline-flex w-fit items-center gap-1.5 rounded-sm text-left text-sm text-fg-primary transition-colors duration-150 enabled:hover:text-brand disabled:cursor-default"
      >
        {running
          ? <IconLoader2 className="size-3.5 motion-safe:animate-spin" />
          : <IconChevronRight className={`size-3.5 transition-transform duration-150 motion-reduce:transition-none ${open ? "rotate-90" : ""}`} />}
        <span className="font-medium">{helper.title}</span>
        <span className="text-xs text-fg-muted">
          {STATUS_WORDS[helper.status]}
          {positions.length > 0 && ` · ${positions.length === 1 ? "Step" : "Steps"} ${positions.join(", ")}`}
        </span>
      </button>
      {said && (
        <p className={`ml-5 text-sm leading-relaxed whitespace-pre-line [overflow-wrap:anywhere] ${helper.report ? "text-fg-body" : "text-fg-muted"}`}>
          {said}
        </p>
      )}
      {open && steps.length > 0 && (
        <ol className="relative mt-2 ml-1">
          {steps.map((step, index) => (
            <StoryEntryRow key={step.position} entry={{ kind: "step", key: `step-${step.position}`, step }} investigation={investigation} connected={index < steps.length - 1} />
          ))}
        </ol>
      )}
    </li>
  )
}
