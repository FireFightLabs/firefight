import { Skeleton } from "@/components/ui/skeleton"

// The same grey as every skeleton in the app, named here since the chat scopes --accent to its own lime.
const BLOCK = "bg-hover"

// The conversation's place while it loads, laid out as the thread is, sitting at the foot where the chat opens: a
// question on the right, then an answer across the column with its steps above it.
export function ThreadSkeleton() {
  return (
    <div role="status" aria-label="Loading the conversation" className="flex min-h-0 flex-1 flex-col justify-end overflow-hidden px-4 py-8">
      <div className="mx-auto flex w-full max-w-3xl flex-col gap-8">
        {TURNS.map((turn) => (
          <div key={turn.question} className="flex flex-col gap-8">
            <Skeleton className={`h-11 self-end rounded-[18px] rounded-br-md ${turn.question} ${BLOCK}`} />
            <div className="flex flex-col gap-3">
              <Skeleton className={`h-4 w-44 ${BLOCK}`} />
              {turn.lines.map((width, line) => (
                <Skeleton key={line} className={`h-3.5 ${width} ${BLOCK}`} />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

const TURNS = [
  { question: "w-1/3", lines: [ "w-full", "w-11/12", "w-2/3" ] },
  { question: "w-1/2", lines: [ "w-full", "w-5/6", "w-full", "w-1/2" ] },
]
