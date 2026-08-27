import { IconSparkles } from "@tabler/icons-react"

import { Skeleton } from "@/components/ui/skeleton"

const SECTIONS: { headingWidth: string; lineWidths: string[] }[] = [
  { headingWidth: "w-44", lineWidths: ["w-full", "w-[96%]", "w-[88%]", "w-[64%]"] },
  { headingWidth: "w-36", lineWidths: ["w-full", "w-[94%]", "w-[97%]", "w-[81%]", "w-[55%]"] },
  { headingWidth: "w-52", lineWidths: ["w-full", "w-[92%]", "w-[68%]"] },
  { headingWidth: "w-40", lineWidths: ["w-[97%]", "w-full", "w-[90%]", "w-[72%]"] },
]

export function PostmortemGeneratingSkeleton() {
  return (
    <div className="mx-auto max-w-4xl px-4 py-12 lg:px-6">
      <div className="mb-12 inline-flex items-center gap-2 rounded-full bg-primary/10 px-3 py-1.5 text-xs font-medium text-primary">
        <IconSparkles className="size-3.5 animate-pulse" />
        Generating postmortem with AI · this usually takes under a minute
      </div>

      <Skeleton className="mb-4 h-11 w-[82%]" />
      <Skeleton className="mb-16 h-3.5 w-[36%]" />

      {SECTIONS.map((section, sectionIndex) => (
        <div key={sectionIndex} className="mb-14">
          <Skeleton className={`mb-6 h-7 ${section.headingWidth}`} />
          <div className="space-y-4">
            {section.lineWidths.map((lineWidth, lineIndex) => (
              <Skeleton key={lineIndex} className={`h-4 ${lineWidth}`} />
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}
