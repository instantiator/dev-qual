/**
 * dev-qual's ESLint flat-config baseline for TypeScript projects.
 *
 * Turns the rules in `guidance/languages/typescript/typescript.md` and
 * `guidance/standards/*.md` into enforced, zero-warning ESLint errors:
 * no `any`, no empty catch blocks, bounded complexity/depth/params/size,
 * and strict equality.
 *
 * To adopt, in the project's own `eslint.config.mjs` (flat config):
 *
 *   import devQualBaseline from "./dev-qual/guidance/languages/typescript/tools/eslint-baseline.mjs";
 *   export default [...projectConfig, ...devQualBaseline];
 *
 * Spread the baseline LAST: in flat config later objects win, so anything
 * after it could quietly weaken these rules. This file only sets rules.
 *
 * NB. This file imports no packages — it is resolved from inside
 * dev-qual's own directory, which has no node_modules of its own. The
 * project's typescript-eslint config (already present for
 * recommended-type-checked, per the TypeScript guidance) registers the
 * `@typescript-eslint` plugin; flat config merges rule objects for the
 * same `files` glob, so scoping rules here to TS files is enough — no
 * plugin import is needed in this file.
 */

const TS_FILES = ["**/*.{ts,tsx,mts,cts}"];
const JS_AND_TS_FILES = ["**/*.{js,jsx,mjs,cjs,ts,tsx,mts,cts}"];
const TEST_FILES = ["**/*.{test,spec}.{ts,tsx,js,mjs}", "**/__tests__/**"];

const devQualBaseline = [
  {
    files: JS_AND_TS_FILES,
    rules: {
      "no-empty": ["error", { allowEmptyCatch: false }],
      complexity: ["error", 10],
      "max-depth": ["error", 4],
      "max-params": ["error", 4],
      "max-lines-per-function": [
        "error",
        { max: 60, skipBlankLines: true, skipComments: true },
      ],
      eqeqeq: "error",
    },
  },
  {
    files: TS_FILES,
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
    },
  },
  {
    files: TEST_FILES,
    rules: {
      "max-lines-per-function": "off",
    },
  },
];

export default devQualBaseline;
