// Re-exported from the generated serializer types. Hand-written copies drifted
// from the server without a type error.
export type {
  CatalogType,
  CatalogEntry,
  CatalogAttributeDefinition as AttributeDefinition,
} from "@/types/serializers";
import type { CatalogAttributeDefinition } from "@/types/serializers";

export type AttributeType = CatalogAttributeDefinition["attributeType"];

export interface ReferenceEntry {
  id: string;
  name: string;
  typeId: string;
}

export type { SlackMember } from "@/hooks/use-member-search";

export type { SlackChannel } from "@/types";

export interface WorkspaceMember {
  id: string;
  name: string;
  avatarUrl?: string;
}
