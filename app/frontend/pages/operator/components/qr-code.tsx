interface QrCodeProps {
  modules: boolean[][];
  label: string;
}

const QUIET_ZONE = 4;

// Drawn from the server's squares, on white with the quiet zone scanners need, whatever the page's theme.
export function QrCode({ modules, label }: QrCodeProps) {
  const size = modules.length + QUIET_ZONE * 2;
  const squares = modules.flatMap((row, rowIndex) =>
    row.flatMap((dark, column) => (dark ? [`M${column + QUIET_ZONE} ${rowIndex + QUIET_ZONE}h1v1h-1z`] : [])),
  );

  return (
    <svg
      role="img"
      aria-label={label}
      viewBox={`0 0 ${size} ${size}`}
      className="size-52 rounded-lg"
      shapeRendering="crispEdges"
    >
      <rect width={size} height={size} fill="#ffffff" />
      <path d={squares.join("")} fill="#04111d" />
    </svg>
  );
}
