// "staging", "staging and production", "dev, staging and production".
export function listed(names: string[]): string {
  if (names.length <= 1) {
    return names[0] ?? ""
  }
  return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`
}
