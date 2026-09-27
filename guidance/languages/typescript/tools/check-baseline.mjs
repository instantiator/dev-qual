#!/usr/bin/env node
/**
 * Verifies that a project has adopted dev-qual's ESLint baseline.
 *
 * Looks for the project's flat-config ESLint file and checks it imports
 * `eslint-baseline.mjs` from this same directory. Prints the exact lines
 * to add when it hasn't, so adoption is copy-paste rather than a search.
 */

import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BASELINE_PATH = path.join(HERE, "eslint-baseline.mjs");
const CONFIG_NAMES = [
  "eslint.config.js",
  "eslint.config.mjs",
  "eslint.config.cjs",
  "eslint.config.ts",
  "eslint.config.mts",
  "eslint.config.cts",
];

const HELP = `check-baseline — verify a project adopts dev-qual's ESLint baseline

Usage:
  node check-baseline.mjs [--project <dir>]

Options:
  --project <dir>  Project directory to check (default: current directory)
  --help           Show this help and exit

Exit codes:
  0  baseline adopted, or the directory is not a Node project
  1  no baseline adoption found (prints the lines to add)
  2  invalid arguments`;

/** Turns an absolute filesystem path into an import specifier: relative
 * (with a leading "./") when `target` sits inside `fromDir`, absolute
 * otherwise. Import specifiers always use forward slashes. */
function toImportSpecifier(fromDir, target) {
  const rel = path.relative(fromDir, target);
  if (rel.startsWith("..")) {
    return target;
  }
  const posixRel = rel.split(path.sep).join("/");
  return posixRel.startsWith(".") ? posixRel : `./${posixRel}`;
}

/** Builds the two lines a project should add to adopt the baseline. */
function adoptionLines(configDir) {
  const importPath = toImportSpecifier(configDir, BASELINE_PATH);
  return [
    `  import devQualBaseline from "${importPath}";`,
    `  export default [/* project config */, ...devQualBaseline]; // baseline last, so it wins`,
  ];
}

/** Finds the project's flat-config ESLint file, if any. */
function findEslintConfig(projectDir) {
  for (const name of CONFIG_NAMES) {
    const candidate = path.join(projectDir, name);
    if (existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
}

/** Checks whether a config file's source references eslint-baseline.mjs. */
function referencesBaseline(configFile) {
  const source = readFileSync(configFile, "utf8");
  return source.includes("eslint-baseline.mjs");
}

/** Runs the adoption check for a project directory, printing the result. */
function checkBaseline(projectDir) {
  if (!existsSync(path.join(projectDir, "package.json"))) {
    console.log("not a node project");
    return 0;
  }

  const configFile = findEslintConfig(projectDir);
  if (!configFile) {
    console.log("No ESLint config found. Add:");
    console.log(adoptionLines(projectDir).join("\n"));
    console.log(
      "  create eslint.config.mjs (see guidance/languages/typescript/typescript.md)",
    );
    return 1;
  }

  if (referencesBaseline(configFile)) {
    console.log(`baseline: adopted (${configFile})`);
    return 0;
  }

  console.log(`${configFile} does not adopt the dev-qual baseline. Add:`);
  console.log(adoptionLines(path.dirname(configFile)).join("\n"));
  return 1;
}

/** Parses argv into { projectDir } or exits 2 on invalid input. */
function parseArgv(argv) {
  let parsed;
  try {
    parsed = parseArgs({
      args: argv,
      options: {
        project: { type: "string" },
        help: { type: "boolean" },
      },
    });
  } catch (error) {
    console.error(`Invalid arguments: ${error.message}`);
    console.error(HELP);
    process.exit(2);
  }

  if (parsed.values.help) {
    console.log(HELP);
    process.exit(0);
  }

  if (parsed.positionals.length > 0) {
    console.error(`Unknown argument: ${parsed.positionals[0]}`);
    console.error(HELP);
    process.exit(2);
  }

  return { projectDir: path.resolve(parsed.values.project ?? ".") };
}

function main() {
  const { projectDir } = parseArgv(process.argv.slice(2));
  process.exit(checkBaseline(projectDir));
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main();
}

export { checkBaseline, findEslintConfig, referencesBaseline, toImportSpecifier };
