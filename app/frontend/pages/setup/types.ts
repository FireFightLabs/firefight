import type { SharedProps } from "@/types"
import type { AiCredits } from "@/components/ai/ai-credits-row"
import type { AiSignIn } from "@/components/ai/ai-accounts-card"
import type {
  AbilityRole,
  AiProviderOption,
  EnvironmentOption,
  OnboardingCategory,
  OnboardingStep,
  Principal,
  WorkspaceAiAccount,
} from "@/types/serializers"

export interface WalkthroughStep {
  title: string
  detail: string
}

export interface SetupPageProps extends SharedProps {
  workspaceName: string
  email: string
  steps: OnboardingStep[]
  aiChoice: string | null
  // Each choice offered, with why it cannot be chosen yet.
  aiChoices: Record<string, string | null>
  aiAccounts: WorkspaceAiAccount[]
  aiProviders: AiProviderOption[]
  aiSignIn: AiSignIn | null
  aiFallback: string
  aiCredits: AiCredits | null
  categories: OnboardingCategory[]
  stackAnswers: Record<string, string>
  environments: EnvironmentOption[]
  principals: Principal[]
  packs: AbilityRole[]
  firstQuestion: string
  walkthrough: WalkthroughStep[]
}
