// The three catalogue shapes come from the serializers. Hand-writing them
// once let the page drift from what the server sends without a type error.
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
