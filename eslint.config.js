import js from "@eslint/js"
import tseslint from "typescript-eslint"
import reactHooks from "eslint-plugin-react-hooks"

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    plugins: {
      "react-hooks": reactHooks,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "@typescript-eslint/no-unused-vars": ["warn", { argsIgnorePattern: "^_" }],
      "@typescript-eslint/no-explicit-any": "warn",
      curly: ["error", "all"],
      "id-length": ["error", { min: 2, exceptions: ["_"], properties: "never" }],
    },
  },
  {
    ignores: [
      "node_modules/",
      // Synced from the cloud engine at build time, not source here.
      "app/frontend/cloud_pages/",
      "app/frontend/lib/routes.ts",
      "app/frontend/lib/routes.d.ts",
      "app/frontend/components/ui/",
    ],
  }
)
