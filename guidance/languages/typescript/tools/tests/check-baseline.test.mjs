import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const TOOLS_DIR = path.join(HERE, "..");
const MODULE_PATH = path.join(TOOLS_DIR, "check-baseline.mjs");
const BASELINE_PATH = path.join(TOOLS_DIR, "eslint-baseline.mjs");

const { checkBaseline, toImportSpecifier } = await import(pathToFileURL(MODULE_PATH).href);

/** Makes a throwaway project directory that is cleaned up by the caller. */
function makeTempProject() {
  return mkdtempSync(path.join(tmpdir(), "check-baseline-"));
}

test("not a node project: no package.json", () => {
  const dir = makeTempProject();
  try {
    let logged = "";
    const restore = captureLog((line) => (logged += line));
    const exitCode = checkBaseline(dir);
    restore();
    assert.equal(exitCode, 0);
    assert.match(logged, /not a node project/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("no eslint config: prints adoption lines and create instruction", () => {
  const dir = makeTempProject();
  writeFileSync(path.join(dir, "package.json"), "{}");
  try {
    let logged = "";
    const restore = captureLog((line) => (logged += line));
    const exitCode = checkBaseline(dir);
    restore();
    assert.equal(exitCode, 1);
    assert.match(logged, /No ESLint config found/);
    assert.match(logged, /import devQualBaseline/);
    assert.match(logged, /create eslint\.config\.mjs/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("config without baseline: prints the correct relative import path", () => {
  const dir = makeTempProject();
  writeFileSync(path.join(dir, "package.json"), "{}");
  writeFileSync(path.join(dir, "eslint.config.mjs"), "export default [];\n");
  try {
    let logged = "";
    const restore = captureLog((line) => (logged += line));
    const exitCode = checkBaseline(dir);
    restore();
    assert.equal(exitCode, 1);
    const expectedPath = toImportSpecifier(dir, BASELINE_PATH);
    assert.ok(
      logged.includes(expectedPath),
      `expected log to include ${expectedPath}, got:\n${logged}`,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("adopted: config already references the baseline", () => {
  const dir = makeTempProject();
  writeFileSync(path.join(dir, "package.json"), "{}");
  const configFile = path.join(dir, "eslint.config.mjs");
  writeFileSync(
    configFile,
    'import devQualBaseline from "./eslint-baseline.mjs";\nexport default [...devQualBaseline];\n',
  );
  try {
    let logged = "";
    const restore = captureLog((line) => (logged += line));
    const exitCode = checkBaseline(dir);
    restore();
    assert.equal(exitCode, 0);
    assert.match(logged, /baseline: adopted/);
    assert.ok(logged.includes(configFile));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("baseline outside the project: uses an absolute path", () => {
  const dir = makeTempProject();
  writeFileSync(path.join(dir, "package.json"), "{}");
  writeFileSync(path.join(dir, "eslint.config.mjs"), "export default [];\n");
  try {
    const specifier = toImportSpecifier(dir, BASELINE_PATH);
    assert.equal(specifier, BASELINE_PATH);
    assert.ok(path.isAbsolute(specifier));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

/** Redirects console.log to a sink for the duration of a test, returning a restore function. */
function captureLog(sink) {
  const original = console.log;
  console.log = (...args) => sink(args.join(" ") + "\n");
  return () => {
    console.log = original;
  };
}
