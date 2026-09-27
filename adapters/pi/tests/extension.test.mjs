// Tests for adapters/pi/extension.mjs against a fake pi API — pi itself
// isn't installed, so these check the extension's own logic: which events
// it registers, and readState()/renderEntry()'s behaviour against temp
// state files, not pi's actual runtime.
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import extension, { readState, renderEntry } from "../extension.mjs";

// A temp git repo, so gitToplevel() resolves the way it would for a real
// project.
function mkTmpRepo() {
  const dir = mkdtempSync(path.join(tmpdir(), "dev-qual-pi-test-"));
  execFileSync("git", ["init", "-q"], { cwd: dir });
  return dir;
}

// A fake pi API that records every pi.on(event, handler) registration.
function fakePi() {
  const handlers = {};
  return { on: (event, handler) => { handlers[event] = handler; }, handlers };
}

test("registers the expected events", () => {
  const { handlers } = (() => {
    const pi = fakePi();
    extension(pi);
    return pi;
  })();
  assert.deepEqual(
    Object.keys(handlers).sort(),
    ["agent_before_settle", "before_agent_start", "session_start", "tool_result"].sort(),
  );
});

test("readState: no state files anywhere -> governing none, no injection", () => {
  const repo = mkTmpRepo();
  const home = mkdtempSync(path.join(tmpdir(), "dev-qual-pi-home-"));
  const { governing, inject } = readState(repo, { HOME: home });
  assert.equal(governing, "none");
  assert.equal(inject, false);
});

test("readState: project .dev-qual.env present -> project governs, never injects", () => {
  const repo = mkTmpRepo();
  writeFileSync(path.join(repo, ".dev-qual.env"), "SCOPE=project\nTIER=local\nENABLED=1\n");
  const home = mkdtempSync(path.join(tmpdir(), "dev-qual-pi-home-"));
  const { governing, inject, state } = readState(repo, { HOME: home });
  assert.equal(governing, "project");
  assert.equal(inject, false, "pi already reads the project's own AGENTS.md");
  assert.equal(state.TIER, "local");
});

test("readState: user config.env governs when there's no project install", () => {
  const repo = mkTmpRepo();
  const home = mkdtempSync(path.join(tmpdir(), "dev-qual-pi-home-"));
  mkdirSync(path.join(home, ".config", "dev-qual"), { recursive: true });
  writeFileSync(path.join(home, ".config", "dev-qual", "config.env"), "SCOPE=user\nTIER=remote\nENABLED=1\n");
  const { governing, inject, state } = readState(repo, { HOME: home });
  assert.equal(governing, "user");
  assert.equal(inject, true);
  assert.equal(state.TIER, "remote");
});

test("readState: user ENABLED=0 -> no injection", () => {
  const repo = mkTmpRepo();
  const home = mkdtempSync(path.join(tmpdir(), "dev-qual-pi-home-"));
  mkdirSync(path.join(home, ".config", "dev-qual"), { recursive: true });
  writeFileSync(path.join(home, ".config", "dev-qual", "config.env"), "SCOPE=user\nTIER=remote\nENABLED=0\n");
  const { inject } = readState(repo, { HOME: home });
  assert.equal(inject, false);
});

test("before_agent_start: appends the tier entry with the checkout path, no bare dev-qual/", () => {
  const repo = mkTmpRepo();
  const home = mkdtempSync(path.join(tmpdir(), "dev-qual-pi-home-"));
  mkdirSync(path.join(home, ".config", "dev-qual"), { recursive: true });
  writeFileSync(path.join(home, ".config", "dev-qual", "config.env"), "SCOPE=user\nTIER=remote\nENABLED=1\n");

  const originalCwd = process.cwd();
  const originalHome = process.env.HOME;
  const originalXdg = process.env.XDG_CONFIG_HOME;
  process.chdir(repo);
  process.env.HOME = home;
  delete process.env.XDG_CONFIG_HOME;
  try {
    const pi = fakePi();
    extension(pi);
    const result = pi.handlers.before_agent_start({ systemPrompt: "base prompt" });
    assert.ok(result.systemPrompt.startsWith("base prompt"));
    const checkoutDir = path.resolve(fileURLToPath(new URL("../../..", import.meta.url)));
    assert.ok(result.systemPrompt.includes(checkoutDir), "prompt names the absolute checkout path");
    assert.ok(
      result.systemPrompt.includes(`${checkoutDir}/guidance/index.md`),
      "a plain dev-qual/ doc reference was rewritten to the checkout path",
    );
  } finally {
    process.chdir(originalCwd);
    if (originalHome === undefined) delete process.env.HOME; else process.env.HOME = originalHome;
    if (originalXdg === undefined) delete process.env.XDG_CONFIG_HOME; else process.env.XDG_CONFIG_HOME = originalXdg;
  }
});

test("before_agent_start: project scope appends nothing", () => {
  const repo = mkTmpRepo();
  writeFileSync(path.join(repo, ".dev-qual.env"), "SCOPE=project\nTIER=local\nENABLED=1\n");
  const home = mkdtempSync(path.join(tmpdir(), "dev-qual-pi-home-"));

  const originalCwd = process.cwd();
  const originalHome = process.env.HOME;
  process.chdir(repo);
  process.env.HOME = home;
  try {
    const pi = fakePi();
    extension(pi);
    const result = pi.handlers.before_agent_start({ systemPrompt: "base prompt" });
    assert.equal(result, undefined);
  } finally {
    process.chdir(originalCwd);
    if (originalHome === undefined) delete process.env.HOME; else process.env.HOME = originalHome;
  }
});

test("renderEntry: rewrites the entry sentence and every other dev-qual/ path", () => {
  const source = "`dev-qual/` is in this repo (or clone <https://github.com/instantiator/dev-qual> to a temporary location once per session).\nAlso read dev-qual/guidance/index.md.";
  const rendered = renderEntry(source, "/abs/checkout");
  assert.ok(rendered.includes("dev-qual is installed at `/abs/checkout`"));
  assert.ok(rendered.includes("/abs/checkout/guidance/index.md"), "the plain doc reference was rewritten");
  assert.ok(!rendered.includes("clone <https://github.com/instantiator/dev-qual>"), "the old sentence is gone");
});
