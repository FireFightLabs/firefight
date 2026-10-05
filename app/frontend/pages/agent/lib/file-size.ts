const UNITS = [ "Bytes", "KB", "MB", "GB" ]
const STEP = 1024

// Before a file is uploaded its size is the browser's, written the way the server writes it once it has the file.
export function fileSize(bytes: number): string {
  let value = bytes
  let unit = 0
  while (value >= STEP && unit < UNITS.length - 1) {
    value /= STEP
    unit += 1
  }

  return `${unit === 0 ? value : Number(value.toPrecision(2))} ${UNITS[unit]}`
}
