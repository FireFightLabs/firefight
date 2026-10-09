import { formatDate } from "@/lib/formatters"
import type { AgentChatMemoryQuestion } from "@/types/serializers"

// Such as: I used to remember "web deploys from main" (from your chat on Oct 3, 2026, confirmed by Ana). The deploy log
// of web shows "web deploys from release". Which is right?
export function askedAboutMemory(question: AgentChatMemoryQuestion): string {
  if (!question.remembered) {
    return question.evidence
  }
  const learned = question.learnedAt ? ` on ${formatDate(question.learnedAt)}` : ""
  return `I used to remember "${question.remembered}" (from ${question.origin}${learned}, ${question.trust}). ${question.evidence} Which is right?`
}
