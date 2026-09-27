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

// A fake pi API that records handler registrations and sent messages.
function fakePi() {
  const handlers = {};
  const sent = [];
  return {
    on: (event, handler) => { handlers[event] = handler; },
    sendMessage: (message, options) => { sent.push({ message, options }); },
    handlers,
    sent,
  };
}

// A project-scope install whose tree fails the fast gate: a shell script
// with a shellcheck finding, uncommitted so the stop gate sees code changed.
function mkFailingProject() {
  const repo = mkTmpRepo();
  const checkout = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
  writeFileSync(path.join(repo, ".dev-qual.env"),
    `SCOPE=project\nTIER=local\nENABLED=1\nCHECKOUT=${checkout}\n`);
  writeFileSync(path.join(repo, "bad.sh"), "#!/usr/bin/env bash\necho $1\n");
  return repo;
}

test("registers the expected events", () => {
  const { handlers } = (() => {
    const pi = fakePi();
    extension(pi);
    return pi;
  })();
  assert.deepEqual(
    Object.keys(handlers).sort(),
    ["agent_end", "before_agent_start", "session_start", "tool_result"].sort(),
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

test("tool_result: non-edit tools are left alone", () => {
  const pi = fakePi();
  extension(pi);
  const repo = mkFailingProject();
  const result = pi.handlers.tool_result({ toolName: "read", content: [] }, { cwd: repo });
  assert.equal(result, undefined);
});

test("tool_result: a failing fast gate is appended to an edit's result", () => {
  const pi = fakePi();
  extension(pi);
  const repo = mkFailingProject();
  const original = { type: "text", text: "edited bad.sh" };
  const result = pi.handlers.tool_result({ toolName: "edit", content: [original] }, { cwd: repo });
  assert.equal(result.content[0], original);
  assert.match(result.content[1].text, /dev-qual post-edit gate/);
  assert.match(result.content[1].text, /shellcheck/);
});

test("agent_end: re-prompts once on a failing gate, then lets the agent stop", () => {
  const pi = fakePi();
  extension(pi);
  const repo = mkFailingProject();
  pi.handlers.agent_end({ messages: [] }, { cwd: repo });
  assert.equal(pi.sent.length, 1);
  assert.equal(pi.sent[0].options.triggerTurn, true);
  assert.match(pi.sent[0].message.content, /dev-qual stop gate/);
  pi.handlers.agent_end({ messages: [] }, { cwd: repo });
  assert.equal(pi.sent.length, 1, "second agent_end in a row is not blocked");
});
