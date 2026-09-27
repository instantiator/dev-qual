import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BASELINE_PATH = path.join(HERE, "..", "eslint-baseline.mjs");

const TS_ANY_RULE = "@typescript-eslint/no-explicit-any";

test("importing the baseline yields an array of config objects", async () => {
  const baseline = (await import(pathToFileURL(BASELINE_PATH).href)).default;
  assert.ok(Array.isArray(baseline));
  assert.ok(baseline.length > 0);
  for (const entry of baseline) {
    assert.equal(typeof entry, "object");
  }
});

test("every @typescript-eslint rule sits in an object scoped to TS files", async () => {
  const baseline = (await import(pathToFileURL(BASELINE_PATH).href)).default;
  const tsEntries = baseline.filter((entry) =>
    Object.keys(entry.rules ?? {}).some((rule) => rule.startsWith("@typescript-eslint/")),
  );
  assert.ok(tsEntries.length > 0, "expected at least one @typescript-eslint rule entry");
  for (const entry of tsEntries) {
    assert.ok(Array.isArray(entry.files), "TS rule entry must scope files");
    assert.ok(
      entry.files.every((glob) => /\.\{?[^}]*ts/.test(glob)),
      `expected TS-only files glob, got ${JSON.stringify(entry.files)}`,
    );
  }
});

test("the listed rules are present as errors", async () => {
  const baseline = (await import(pathToFileURL(BASELINE_PATH).href)).default;
  // Exclude the test-file override entry, which deliberately turns a rule off.
  const baseEntries = baseline.filter(
    (entry) => !(entry.files ?? []).some((glob) => glob.includes("test") || glob.includes("__tests__")),
  );
  const allRules = Object.assign({}, ...baseEntries.map((entry) => entry.rules ?? {}));

  const expectedSeverityOf = (value) => (Array.isArray(value) ? value[0] : value);

  assert.equal(expectedSeverityOf(allRules[TS_ANY_RULE]), "error");
  assert.equal(expectedSeverityOf(allRules["no-empty"]), "error");
  assert.deepEqual(allRules["no-empty"], ["error", { allowEmptyCatch: false }]);
  assert.equal(expectedSeverityOf(allRules.complexity), "error");
  assert.equal(allRules.complexity[1], 10);
  assert.equal(expectedSeverityOf(allRules["max-depth"]), "error");
  assert.equal(allRules["max-depth"][1], 4);
  assert.equal(expectedSeverityOf(allRules["max-params"]), "error");
  assert.equal(allRules["max-params"][1], 4);
  assert.equal(expectedSeverityOf(allRules["max-lines-per-function"]), "error");
  assert.equal(allRules["max-lines-per-function"][1].max, 60);
  assert.equal(allRules["max-lines-per-function"][1].skipBlankLines, true);
  assert.equal(allRules["max-lines-per-function"][1].skipComments, true);
  assert.equal(expectedSeverityOf(allRules.eqeqeq), "error");
});

test("the test-file override disables max-lines-per-function", async () => {
  const baseline = (await import(pathToFileURL(BASELINE_PATH).href)).default;
  const testEntry = baseline.find(
    (entry) =>
      Array.isArray(entry.files) &&
      entry.files.some((glob) => glob.includes("test") || glob.includes("__tests__")),
  );
  assert.ok(testEntry, "expected a test-file override entry");
  assert.equal(testEntry.rules["max-lines-per-function"], "off");
});
