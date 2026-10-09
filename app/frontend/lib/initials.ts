// An avatar without a picture shows the first letter of the first and last names, or of the only one.
export function initialsOf(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean)
  if (words.length === 0) {
    return ""
  }
  const named = words.length === 1 ? words : [words[0], words[words.length - 1]]
  return named.map(firstLetter).join("").toUpperCase()
}

// A letter outside the basic plane is two code units, so it is taken whole.
function firstLetter(word: string): string {
  return Array.from(word)[0] ?? ""
}
