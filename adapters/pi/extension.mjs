// dev-qual pi extension. Wires the pi coding agent (github.com/badlogic/pi-mono)
// into the same install as Claude Code and OpenCode: the AGENTS.md entry for
// a user-scope install, the session-start update check, and the post-edit /
// stop quality gates via scripts/agent-hook.sh.
//
// Verified against pi's docs on 2026-09-27 (packages.md, extensions.md,
// configuration.md — no other source trusted):
// - extensions are plain files with a default export `(pi) => {...}`,
//   loaded from `.ts`/`.js` (or a directory with an index); registration is
//   `pi.on(eventName, handler)`.
// - events include session_start, before_agent_start, tool_call, tool_result,
//   agent_before_settle, agent_settled.
// - before_agent_start "exposes both the current prompt and its structured
//   systemPromptOptions"; returning `systemPrompt` replaces the prompt for
//   that run — there is no separate append field, so appending means
//   returning the current prompt plus our text.
// - tool_result handlers "compose, with each handler seeing prior changes" —
//   the only documented way for this event to add text back for the model.
// - agent_before_settle "is the final actionable boundary: it can append
//   entries and request one continuation" via `{ continue: true }".
// - ctx.ui.notify(message, level) surfaces text outside a prompt/result.
// - configuration.md's "context files" section confirms pi auto-loads
//   AGENTS.md/CLAUDE.md from the project directory and its parents itself,
//   without project trust — see readState() below for what that means here.
//
// Not documented anywhere in the fetched pages: a dedicated shell-exec API
// (no `pi.exec`), so hooks are run with node:child_process like any other
// Node ESM module; and the exact field names on tool_call/tool_result events
// (tool name, result text), so those are read defensively with fallbacks.

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
// returning its outcome instead of throwing on the exit-2 "block" case that
// post-edit/stop use.
function runHook(event, scope, stdin) {
  try {
    const stdout = execFileSync(
      "bash",
      [path.join(CHECKOUT_DIR, "scripts", "agent-hook.sh"), event, "--scope", scope],
      { input: stdin ?? "", encoding: "utf8" },
    );
    return { code: 0, stdout, stderr: "" };
  } catch (err) {
    return { code: err.status ?? 1, stdout: err.stdout ?? "", stderr: err.stderr ?? "" };
  }
}

// True when a tool_call/tool_result event looks like an edit — pi's exact
// tool-name field isn't confirmed in the fetched docs, so this checks the
// common candidate fields defensively rather than picking one.
function looksLikeEditTool(event) {
  const name = event.tool ?? event.toolName ?? event.name ?? "";
  return /edit|write/i.test(name);
}

export default function (pi) {
  // Append dev-qual's entry instructions for a user-scope install. Project
  // scope is intentionally skipped — see readState()'s comment.
  pi.on("before_agent_start", (event) => {
    const { inject, state } = readState(process.cwd(), process.env);
    if (!inject) return undefined;
    const current = event.systemPrompt ?? "";
    return { systemPrompt: `${current}\n\n${tierEntry(state)}` };
  });

  // Non-blocking update check, surfaced through the UI notification API.
  pi.on("session_start", (event, ctx) => {
    const { governing } = readState(process.cwd(), process.env);
    if (governing === "none") return undefined;
    const { stdout } = runHook("session-start", governing);
    if (stdout.trim() && ctx?.ui?.notify) ctx.ui.notify(stdout.trim(), "info");
    return undefined;
  });

  // Post-edit gate: fold a failing fast check into the edit tool's own
  // result, the only documented way for tool_result to add text back for
  // the model (handlers "compose, with each handler seeing prior changes").
  pi.on("tool_result", (event) => {
    if (!looksLikeEditTool(event)) return undefined;
    const { governing, state } = readState(process.cwd(), process.env);
    if (governing === "none" || state.ENABLED !== "1") return undefined;
    const { code, stderr } = runHook("post-edit", governing);
    if (code === 0) return undefined;
    return { result: `${event.result ?? ""}\n\ndev-qual post-edit gate:\n${stderr}` };
  });

  // Stop gate: agent_before_settle is the last point that can both append
  // an entry and request one continuation, matching Claude Code's Stop
  // hook. agent-hook.sh itself refuses to block twice in a row (it reads
  // stop_hook_active from stdin), so this can't loop.
  pi.on("agent_before_settle", (event) => {
    const { governing, state } = readState(process.cwd(), process.env);
    if (governing === "none" || state.ENABLED !== "1") return undefined;
    const stdin = JSON.stringify({ stop_hook_active: Boolean(event.stopHookActive) });
    const { code, stderr } = runHook("stop", governing, stdin);
    if (code === 0) return undefined;
    return { appendEntry: stderr, continue: true };
  });
}
