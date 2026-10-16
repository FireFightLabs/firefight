import type { SharedProps } from "@/types"
import type { AiCredits } from "@/components/ai/ai-credits-row"
import type { CreditPurchase } from "@/components/ai/credit-packs"
import type { AiSignIn } from "@/components/ai/ai-accounts-card"
import type {
  AiProviderOption,
  EnvironmentOption,
  MemberAccess,
  OnboardingCategory,
  OnboardingStep,
  SetupAiChoice,
  SetupPlan,
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
  // The plan a hosted build sells, absent where none is sold.
  plan: SetupPlan | null
  // The step to open on, when someone comes back to one from paying for credits.
  openStep: string | null
  aiChoice: string | null
  // Each choice offered, in its words, with why it cannot be chosen yet.
  aiChoices: SetupAiChoice[]
  aiAccounts: WorkspaceAiAccount[]
  aiProviders: AiProviderOption[]
  aiSignIn: AiSignIn | null
  aiFallback: string
  aiCredits: AiCredits | null
  aiCreditPurchase: CreditPurchase | null
  categories: OnboardingCategory[]
  stackAnswers: Record<string, string>
  environments: EnvironmentOption[]
  // What members can read and change in each connection, as the Permissions screen also shows it.
  memberAccess: MemberAccess
  firstQuestion: string
  walkthrough: WalkthroughStep[]
}
