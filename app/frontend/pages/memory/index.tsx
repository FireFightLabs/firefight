import { Head, usePage } from "@inertiajs/react"
import { useState } from "react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { useCan } from "@/lib/permissions"
import { InstructionsTab } from "@/pages/memory/components/instructions-tab"
import { MemoriesTab } from "@/pages/memory/components/memories-tab"
import { MEMORY_PAGE_TAB_QUERY, MEMORY_PAGE_TABS, MEMORY_QUERY_PARAM } from "@/lib/generated/constants"
import type { MemoryPageProps, MemoryTab } from "@/pages/memory/types"
import { replaceQuery } from "@/lib/query"

function tabFromUrl(): MemoryTab {
  const requested = new URLSearchParams(window.location.search).get(MEMORY_PAGE_TAB_QUERY)
  return Object.values(MEMORY_PAGE_TABS).find((tab) => tab === requested) ?? MEMORY_PAGE_TABS.MEMORIES
}

function memoryFromUrl(): string | null {
  return new URLSearchParams(window.location.search).get(MEMORY_QUERY_PARAM)
}

export default function MemoryPage() {
  const { memories, instructions, subjects } = usePage<MemoryPageProps>().props
  const canDecide = useCan("memory")
  const canInstruct = useCan("catalog")
  const [ tab, setTab ] = useState(tabFromUrl)
  const [ focusedId ] = useState(memoryFromUrl)
  // An expired memory was set aside already, so it no longer waits on anyone.
  const toReview = memories.filter((memory) => !memory.confirmBlockedReason && memory.state !== "expired").length

  function switchTab(value: string) {
    const chosen = Object.values(MEMORY_PAGE_TABS).find((each) => each === value)
    if (!chosen) {
      return
    }
    setTab(chosen)
    replaceQuery({ [MEMORY_PAGE_TAB_QUERY]: chosen })
  }

  return (
    <AuthenticatedLayout title="Memory">
      <Head title="Memory" />
      <Tabs value={tab} onValueChange={switchTab} className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <TabsList>
          <TabsTrigger value={MEMORY_PAGE_TABS.MEMORIES} className="gap-1.5 px-3">
            Memories
            {toReview > 0 && (
              <span className="rounded-full bg-warning-tint px-1.5 text-[11px] font-medium text-warning tabular-nums" aria-label={`${toReview} waiting on a person`} title={`${toReview} waiting on a person`}>
                {toReview}
              </span>
            )}
          </TabsTrigger>
          <TabsTrigger value={MEMORY_PAGE_TABS.INSTRUCTIONS} className="px-3">
            Instructions
          </TabsTrigger>
        </TabsList>
        <TabsContent value={MEMORY_PAGE_TABS.MEMORIES}>
          <MemoriesTab memories={memories} subjects={subjects} canCurate={canDecide} focusedId={focusedId} />
        </TabsContent>
        <TabsContent value={MEMORY_PAGE_TABS.INSTRUCTIONS}>
          <InstructionsTab instructions={instructions} subjects={subjects} canCurate={canInstruct} />
        </TabsContent>
      </Tabs>
    </AuthenticatedLayout>
  )
}
