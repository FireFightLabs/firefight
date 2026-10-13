import type { HalonSkill, HalonSkillProposal } from "@/types/serializers"

// The skill dialog writes a new skill, edits one, or edits what Halon proposed before accepting it.
export type SkillDialogState =
  | { mode: "create" }
  | { mode: "edit"; skill: HalonSkill }
  | { mode: "proposal"; proposal: HalonSkillProposal }
  | null
