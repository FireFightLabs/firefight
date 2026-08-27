import {
  IconAsterisk,
  IconBinaryTree2,
  IconForms,
  IconLink,
  IconListDetails,
} from "@tabler/icons-react"

export function FieldTypeIcon({ fieldType }: { fieldType: string }) {
  switch (fieldType) {
    case "number":
      return <IconAsterisk className="size-4" />
    case "link":
      return <IconLink className="size-4" />
    case "single_select":
    case "multi_select":
      return <IconListDetails className="size-4" />
    case "catalog_reference":
    case "catalog_multi_reference":
      return <IconBinaryTree2 className="size-4" />
    default:
      return <IconForms className="size-4" />
  }
}
