// dev-qual pi extension. Wires the pi coding agent (github.com/badlogic/pi-mono)
// into the same install as Claude Code and OpenCode: the AGENTS.md entry for
// a user-scope install, the session-start update check, and the post-edit /
// stop quality gates via scripts/agent-hook.sh.
//
// Written against the extension types shipped in
// @mariozechner/pi-coding-agent 0.73.1 (dist/core/extensions/types.d.ts),
// which is what `npm i -g` installs; the docs on pi's main branch describe
// newer events (e.g. agent_before_settle) that release does not have.
// - default export `(pi) => {...}`; `pi.on(event, (event, ctx) => result)`,
//   with `ctx.cwd` the session's working directory.
// - before_agent_start: `event.systemPrompt`; returning `{ systemPrompt }`
//   replaces it for that turn.
// - tool_result: `event.toolName` ("edit", "write", ...) and
//   `event.content` (text/image parts); returning `{ content }` replaces
//   what the model sees.
// - agent_end: fired when a run finishes, with no result. An extension
//   continues the agent with `pi.sendMessage(msg, { triggerTurn: true })`.
// - pi.sendMessage({ customType, content, display }) puts a message in the
//   session the model reads; `deliverAs: "nextTurn"` queues it.
// - pi reads AGENTS.md from the project and its parents itself.

import { execFileSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// The dev-qual checkout: two levels up from adapters/pi/.
const CHECKOUT_DIR = path.resolve(fileURLToPath(new URL("../..", import.meta.url)));

// Parse a `KEY=value` state file (as install.sh writes with `printf '%q'`)
// into a plain object. Handles the plain values dev-qual writes (words,
// commas, path separators, single/double-quoted); it is not a full shell
// unquoter.
function parseState(text) {
  const state = {};
  for (const line of text.split("\n")) {
    const m = /^([A-Z_]+)=(.*)$/.exec(line.trim());
    if (!m) continue;
    let value = m[2];
    if ((value.startsWith("'") && value.endsWith("'")) || (value.startsWith('"') && value.endsWith('"'))) {
      value = value.slice(1, -1);
    }
    state[m[1]] = value;
  }
  return state;
}

// Read and parse a state file, or null if it doesn't exist.
function readStateFile(filePath) {
  if (!existsSync(filePath)) return null;
  return parseState(readFileSync(filePath, "utf8"));
}

// The project's git toplevel, or cwd itself when it isn't a git repo —
// matches agent-hook.sh's own resolution.
function gitToplevel(cwd) {
  try {
    return execFileSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
  } catch {
    return cwd;
  }
}

// scripts/lib/common.sh's state_file_for(), user scope.
function userStatePath(env) {
  const configHome = env.XDG_CONFIG_HOME || path.join(env.HOME || "", ".config");
  return path.join(configHome, "dev-qual", "config.env");
}

// Work out which install governs `cwd`, and whether this extension should
// inject its own copy of the AGENTS.md entry.
//
// Project scope wins when a `.dev-qual.env` exists there: pi already
// auto-loads AGENTS.md from the project directory itself (configuration.md's
// "context files" — discovery "does not require project trust"), and
// install.sh's project-scope run already merged the dev-qual block into that
// same AGENTS.md. Injecting again here would show the agent the same
// instructions twice, so `inject` is always false for project scope.
// User scope has no such file for pi to find on its own, so this extension
// injects the tier entry itself, the way the OpenCode adapter does for its
// own user-scope config.
export function readState(cwd, env) {
  const projectStatePath = path.join(gitToplevel(cwd), ".dev-qual.env");
  const project = readStateFile(projectStatePath);
  if (project) {
    return { governing: "project", state: project, inject: false };
  }
  const user = readStateFile(userStatePath(env));
  if (!user) return { governing: "none", state: null, inject: false };
  return { governing: "user", state: user, inject: user.ENABLED === "1" };
}

// Mirrors scripts/lib/common.sh's render_entry(), user-scope branch: swap
// the "dev-qual/ is in this repo..." sentence for one naming the checkout,
// then rewrite every other `dev-qual/` path the same way.
export function renderEntry(tierFileContent, checkoutAbs) {
  const placeholder = "@@DEV_QUAL_SENTENCE@@";
  const oldSentence =
    "`dev-qual/` is in this repo (or clone <https://github.com/instantiator/dev-qual> to a temporary location once per session).";
  const newSentence = `dev-qual is installed at \`${checkoutAbs}\`: read every \`dev-qual/\` path in its docs as \`${checkoutAbs}/\`.`;
  let content = tierFileContent.split(oldSentence).join(placeholder);
  content = content.split("dev-qual/").join(`${checkoutAbs}/`);
  content = content.split(placeholder).join(newSentence);
  return content;
}

// The rendered tier entry for a user-scope state (TIER defaults to remote).
function tierEntry(state) {
  const tier = state.TIER === "local" ? "local" : "remote";
  const tierFile = path.join(CHECKOUT_DIR, "agents-files", tier, "AGENTS.md");
  return renderEntry(readFileSync(tierFile, "utf8"), CHECKOUT_DIR);
}

// Run scripts/agent-hook.sh <event> --scope <scope>, feeding it stdin and
// in the session's directory (pinned via CLAUDE_PROJECT_DIR, which the
// script prefers over its cwd), returning its outcome instead of throwing on the exit-2 "block" case that
// post-edit/stop use.
function runHook(event, scope, cwd, stdin) {
  try {
    const stdout = execFileSync(
      "bash",
      [path.join(CHECKOUT_DIR, "scripts", "agent-hook.sh"), event, "--scope", scope],
      { input: stdin ?? "", encoding: "utf8", cwd, env: { ...process.env, CLAUDE_PROJECT_DIR: cwd } },
    );
    return { code: 0, stdout, stderr: "" };
  } catch (err) {
    return { code: err.status ?? 1, stdout: err.stdout ?? "", stderr: err.stderr ?? "" };
  }
}

// Tools whose results can leave the tree failing the fast gate.
const EDIT_TOOLS = new Set(["edit", "write"]);

// A session message the model reads, labelled as dev-qual's.
function devQualMessage(text) {
  return { customType: "dev-qual", content: text, display: true };
}

export default function (pi) {
  // Set when the stop gate re-prompted the agent, so the next agent_end is
  // reported as a re-invocation and agent-hook.sh lets it through: the gate
  // blocks at most once in a row, like Claude Code's stop_hook_active.
  let stopGateFired = false;

  // Append dev-qual's entry instructions for a user-scope install. Project
  // scope is intentionally skipped — see readState()'s comment.
  pi.on("before_agent_start", (event, ctx) => {
    const { inject, state } = readState(ctx?.cwd ?? process.cwd(), process.env);
    if (!inject) return undefined;
    return { systemPrompt: `${event.systemPrompt ?? ""}\n\n${tierEntry(state)}` };
  });

  // Non-blocking update check; queued so the model sees it on its next turn.
  pi.on("session_start", (event, ctx) => {
    const cwd = ctx?.cwd ?? process.cwd();
    const { governing } = readState(cwd, process.env);
    if (governing === "none") return undefined;
    const { stdout } = runHook("session-start", governing, cwd);
    if (stdout.trim()) pi.sendMessage(devQualMessage(stdout.trim()), { deliverAs: "nextTurn" });
    return undefined;
  });

  // Post-edit gate: append a failing fast check to the edit's own result.
  pi.on("tool_result", (event, ctx) => {
    if (!EDIT_TOOLS.has(event.toolName)) return undefined;
    const cwd = ctx?.cwd ?? process.cwd();
    const { governing, state } = readState(cwd, process.env);
    if (governing === "none" || state.ENABLED !== "1") return undefined;
    const { code, stderr } = runHook("post-edit", governing, cwd);
    if (code !== 2) return undefined;
    const note = { type: "text", text: `dev-qual post-edit gate:\n${stderr}` };
    return { content: [...(event.content ?? []), note] };
  });

  // Stop gate: when a run ends with failing checks or unticked plan stages,
  // re-prompt the agent once with what agent-hook.sh reported.
  pi.on("agent_end", (event, ctx) => {
    const cwd = ctx?.cwd ?? process.cwd();
    const { governing, state } = readState(cwd, process.env);
    if (governing === "none" || state.ENABLED !== "1") return undefined;
    const stdin = JSON.stringify({ stop_hook_active: stopGateFired });
    stopGateFired = false;
    const { code, stderr } = runHook("stop", governing, cwd, stdin);
    if (code !== 2) return undefined;
    stopGateFired = true;
    pi.sendMessage(devQualMessage(stderr), { triggerTurn: true });
    return undefined;
  });
}
