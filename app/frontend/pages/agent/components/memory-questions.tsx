import { MemoryQuestionCard } from "@/pages/agent/components/memory-question-card"
import type { AgentChatMemoryQuestion } from "@/types/serializers"

export function MemoryQuestions({ questions }: { questions: AgentChatMemoryQuestion[] | undefined }) {
  return questions?.map((question) => <MemoryQuestionCard key={question.id} question={question} />)
}
