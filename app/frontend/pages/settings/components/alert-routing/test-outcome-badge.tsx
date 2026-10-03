import type { PolicyRule } from "@/types/serializers"
import type { TestResult } from "@/pages/settings/lib/alerts"
import { Badge } from "@/components/ui/badge"

export function TestOutcomeBadge({ rule, testResult }: { rule: PolicyRule; testResult: TestResult | null }) {
  const entry = testResult?.trace.find((trace) => trace.rule_id === rule.id)
  if (!entry) {
    return null
  }

  if (entry.matched) {
    return <Badge className="ml-2">✓ fires</Badge>
  }
  if (entry.skipped) {
    return <span className="ml-2 text-xs text-fg-muted">skipped (disabled)</span>
  }
  return <span className="ml-2 text-xs text-fg-muted">✗ no match</span>
}
