import { useState } from "react"
import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { SKILL_PAGE_QUERIES } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import type { SharedProps } from "@/types"
import type { HalonLibrarySkill, HalonSkill, HalonSkillProposal, HalonSkillToolChoice, HalonSkillVersion } from "@/types/serializers"
import { ImportSkillDialog } from "@/pages/halon/components/skills/import-skill-dialog"
import { LibraryCard } from "@/pages/halon/components/skills/library-card"
import { ProposalsCard } from "@/pages/halon/components/skills/proposals-card"
import { SkillDialog } from "@/pages/halon/components/skills/skill-dialog"
import { SkillsCard } from "@/pages/halon/components/skills/skills-card"
import type { SkillDialogState } from "@/pages/halon/components/skills/types"

interface SkillsPageProps extends SharedProps {
  skills: HalonSkill[]
  proposals: HalonSkillProposal[]
  library: HalonLibrarySkill[]
  toolChoices?: HalonSkillToolChoice[]
  librarySkill?: HalonLibrarySkill | null
  history?: HalonSkillVersion[] | null
}

// A link from the card in a chat opens Halon's proposal here, ready to edit before accepting.
function proposalFromAddress(proposals: HalonSkillProposal[]): SkillDialogState {
  const wanted = new URLSearchParams(window.location.search).get(SKILL_PAGE_QUERIES.PROPOSAL)
  const proposal = proposals.find((each) => each.id === wanted)
  return proposal ? { mode: "proposal", proposal } : null
}

export default function HalonSkillsPage() {
  const { skills, proposals, library, toolChoices, librarySkill, history } = usePage<SkillsPageProps>().props
  const canManage = useCan("skills")
  const [ dialog, setDialog ] = useState<SkillDialogState>(() => (canManage ? proposalFromAddress(proposals) : null))
  const [ importing, setImporting ] = useState(false)

  function openCreate() {
    setDialog({ mode: "create" })
  }

  function openEdit(skill: HalonSkill) {
    setDialog({ mode: "edit", skill })
  }

  function openProposal(proposal: HalonSkillProposal) {
    setDialog({ mode: "proposal", proposal })
  }

  function closeDialog() {
    setDialog(null)
  }

  function openImport() {
    setImporting(true)
  }

  function closeImport() {
    setImporting(false)
  }

  return (
    <AuthenticatedLayout title="Skills">
      <Head title="Skills" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <p className="max-w-prose text-sm text-fg-secondary">
          A skill is a short recipe Halon loads when a question fits: when it is used, the tools it needs and its steps. Halon
          sees each one in a line and loads the steps only when it needs them, so a skill costs nothing until it is used.
        </p>
        {proposals.length > 0 && <ProposalsCard proposals={proposals} canDecide={canManage} onEdit={openProposal} />}
        <SkillsCard skills={skills} history={history} canManage={canManage} onCreate={openCreate} onImport={openImport} onEdit={openEdit} />
        <LibraryCard library={library} librarySkill={librarySkill} canManage={canManage} />
      </div>
      {canManage && <SkillDialog state={dialog} toolChoices={toolChoices} onClose={closeDialog} />}
      {canManage && <ImportSkillDialog open={importing} onClose={closeImport} />}
    </AuthenticatedLayout>
  )
}
