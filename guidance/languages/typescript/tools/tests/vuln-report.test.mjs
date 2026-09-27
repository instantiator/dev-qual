import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const TOOLS_DIR = path.join(HERE, "..");
const MODULE_PATH = path.join(TOOLS_DIR, "vuln-report.mjs");
const FIXTURES_DIR = path.join(HERE, "fixtures");

const { buildReport, describeAction } = await import(pathToFileURL(MODULE_PATH).href);

function loadFixture(name) {
  return JSON.parse(readFileSync(path.join(FIXTURES_DIR, name), "utf8"));
}

test("describeAction covers all three fixAvailable shapes", () => {
  assert.equal(describeAction(true), "npm audit fix");
  assert.equal(
    describeAction(false),
    "no fix available — consider replacing or an override (see guidance/standards/dependencies.md)",
  );
  assert.equal(
    describeAction({ name: "foo", version: "2.0.0", isSemVerMajor: false }),
    "npm install foo@2.0.0",
  );
  assert.equal(
    describeAction({ name: "foo", version: "3.0.0", isSemVerMajor: true }),
    "npm install foo@3.0.0  (MAJOR — ask the user first)",
  );
});

test("ranks by severity then direct-before-transitive", () => {
  const { text, exitCode } = buildReport(loadFixture("vuln-mixed.json"));
  assert.equal(exitCode, 1);
  const lines = text.split("\n").filter((line) => /^[A-Z]+\s/.test(line));

  // critical (minimist, direct) first
  assert.match(lines[0], /^CRITICAL\s+minimist/);
  // both high severity: big-major (direct) before lodash (transitive)
  assert.match(lines[1], /^HIGH\s+big-major/);
  assert.match(lines[2], /^HIGH\s+lodash/);
  // both moderate: old-thing (direct) before trans-mod (transitive)
  assert.match(lines[3], /^MODERATE\s+old-thing/);
  assert.match(lines[4], /^MODERATE\s+trans-mod/);
});

test("each row shows severity, package, range, directness, and action", () => {
  const { text } = buildReport(loadFixture("vuln-mixed.json"));
  assert.match(text, /CRITICAL\s+minimist\s+<1\.2\.6\s+direct\s+npm install minimist@1\.2\.6/);
  assert.match(text, /HIGH\s+lodash\s+>=4\.0\.0 <4\.17\.21\s+transitive\s+npm audit fix/);
  assert.match(
    text,
    /MODERATE\s+old-thing\s+\*\s+direct\s+no fix available/,
  );
  assert.match(
    text,
    /HIGH\s+big-major\s+<2\.0\.0\s+direct\s+npm install big-major@3\.0\.0\s+\(MAJOR — ask the user first\)/,
  );
});

test("summary line reports counts and next steps", () => {
  const { text } = buildReport(loadFixture("vuln-mixed.json"));
  assert.match(text, /Summary: 5 vulnerable package\(s\)/);
  assert.match(text, /1 critical/);
  assert.match(text, /2 high/);
  assert.match(text, /2 moderate/);
  assert.match(text, /Next: apply fixes in small groups, security first/);
  assert.match(text, /skills\/deps-audit/);
});

test("empty vulnerabilities: exit 0, no packages listed", () => {
  const { text, exitCode } = buildReport(loadFixture("vuln-empty.json"));
  assert.equal(exitCode, 0);
  assert.match(text, /No vulnerabilities/);
});

test("CLI: malformed JSON via --input exits 2", () => {
  const inputPath = path.join(FIXTURES_DIR, "vuln-malformed.json");
  assert.throws(() => {
    execFileSync("node", [MODULE_PATH, "--input", inputPath], { encoding: "utf8" });
  }, (error) => error.status === 2);
});

test("CLI: empty vulnerabilities via --input exits 0", () => {
  const inputPath = path.join(FIXTURES_DIR, "vuln-empty.json");
  const output = execFileSync("node", [MODULE_PATH, "--input", inputPath], { encoding: "utf8" });
  assert.match(output, /No vulnerabilities/);
});

test("CLI: mixed vulnerabilities via --input exits 1", () => {
  const inputPath = path.join(FIXTURES_DIR, "vuln-mixed.json");
  try {
    execFileSync("node", [MODULE_PATH, "--input", inputPath], { encoding: "utf8" });
    assert.fail("expected non-zero exit");
  } catch (error) {
    assert.equal(error.status, 1);
    assert.match(error.stdout, /CRITICAL\s+minimist/);
  }
});
