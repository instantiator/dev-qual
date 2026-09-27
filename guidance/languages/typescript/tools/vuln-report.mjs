#!/usr/bin/env node
/**
 * Turns `npm audit --json` into a ranked, actionable next-steps report.
 *
 * npm audit exits non-zero when vulnerabilities exist — that's expected —
 * so this reads stdout regardless of the child process's exit code.
 *
 * JSON shape (npm v7+, verified against a live `npm audit --json` run):
 * `vulnerabilities` is an object keyed by package name, each entry with
 * `name`, `severity`, `isDirect`, `via`, `range`, and `fixAvailable`, where
 * `fixAvailable` is `true`, `false`, or `{ name, version, isSemVerMajor }`.
 */

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

const HELP = `vuln-report — ranked, actionable npm audit report

Usage:
  node vuln-report.mjs [--project <dir>] [--input <file>]

Options:
  --project <dir>  Project to audit (default: current directory)
  --input <file>   Read npm audit --json output from this file instead of
                    running npm (for tests / offline review)
  --help           Show this help and exit

Exit codes:
  0  no vulnerabilities
  1  vulnerabilities found (report printed)
  2  error (bad JSON, npm missing, or audit could not run)`;

const SEVERITY_ORDER = ["critical", "high", "moderate", "low", "info"];

/** Decides the remediation action for one vulnerable package's fixAvailable. */
function describeAction(fixAvailable) {
  if (fixAvailable === true) {
    return "npm audit fix";
  }
  if (fixAvailable === false) {
    return "no fix available — consider replacing or an override (see guidance/standards/dependencies.md)";
  }
  const target = `npm install ${fixAvailable.name}@${fixAvailable.version}`;
  return fixAvailable.isSemVerMajor ? `${target}  (MAJOR — ask the user first)` : target;
}

/** Builds one report row for a vulnerable package. */
function toRow(vuln) {
  const directness = vuln.isDirect ? "direct" : "transitive";
  return {
    severity: vuln.severity,
    name: vuln.name,
    range: vuln.range,
    directness,
    action: describeAction(vuln.fixAvailable),
  };
}

/** Ranks rows by severity (critical first), then direct before transitive. */
function rankRows(rows) {
  return [...rows].sort((a, b) => {
    const severityDiff = SEVERITY_ORDER.indexOf(a.severity) - SEVERITY_ORDER.indexOf(b.severity);
    if (severityDiff !== 0) {
      return severityDiff;
    }
    if (a.directness === b.directness) {
      return a.name.localeCompare(b.name);
    }
    return a.directness === "direct" ? -1 : 1;
  });
}

/** Formats one row as a fixed-column report line. */
function formatRow(row) {
  const severity = row.severity.toUpperCase().padEnd(8);
  return `${severity}  ${row.name}  ${row.range}  ${row.directness}  ${row.action}`;
}

/** Builds the full report text and exit code from a parsed audit report. */
function buildReport(auditReport) {
  const vulnerabilities = auditReport.vulnerabilities ?? {};
  const rows = rankRows(Object.values(vulnerabilities).map(toRow));

  if (rows.length === 0) {
    return { text: "No vulnerabilities found.", exitCode: 0 };
  }

  const counts = SEVERITY_ORDER.map(
    (severity) => `${rows.filter((row) => row.severity === severity).length} ${severity}`,
  ).join(", ");

  const lines = [
    ...rows.map(formatRow),
    "",
    `Summary: ${rows.length} vulnerable package(s) (${counts}).`,
    "Next: apply fixes in small groups, security first, running check.sh after each (skills/deps-audit)",
  ];

  return { text: lines.join("\n"), exitCode: 1 };
}

/** Runs `npm audit --json` in a project dir and returns its stdout. */
function runNpmAudit(projectDir) {
  try {
    return execFileSync("npm", ["audit", "--json"], {
      cwd: projectDir,
      encoding: "utf8",
    });
  } catch (error) {
    // npm audit exits non-zero when vulnerabilities exist — that's expected,
    // and its JSON report is still on stdout in that case.
    if (typeof error.stdout === "string" && error.stdout.length > 0) {
      return error.stdout;
    }
    throw error;
  }
}

/** Loads the raw audit JSON text, from --input or by running npm. */
function loadAuditJson(options) {
  if (options.input) {
    return readFileSync(options.input, "utf8");
  }
  return runNpmAudit(options.projectDir);
}

/** Parses argv into { projectDir, input } or exits 2 on invalid input. */
function parseArgv(argv) {
  let parsed;
  try {
    parsed = parseArgs({
      args: argv,
      options: {
        project: { type: "string" },
        input: { type: "string" },
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

  return {
    projectDir: path.resolve(parsed.values.project ?? "."),
    input: parsed.values.input,
  };
}

function main() {
  const options = parseArgv(process.argv.slice(2));

  let rawJson;
  try {
    rawJson = loadAuditJson(options);
  } catch (error) {
    console.error(`vuln-report: could not run npm audit: ${error.message}`);
    process.exit(2);
  }

  let auditReport;
  try {
    auditReport = JSON.parse(rawJson);
  } catch (error) {
    console.error(`vuln-report: could not parse npm audit output: ${error.message}`);
    process.exit(2);
  }

  // npm reports its own failures (e.g. ENOLOCK: no lockfile) as JSON too.
  // Treat anything without a `vulnerabilities` object as a failed audit, so
  // it can never read as an all-clear.
  if (auditReport.error || typeof auditReport.vulnerabilities !== "object") {
    const { code = "unknown", summary = "unexpected npm audit output", detail = "" } =
      auditReport.error ?? {};
    console.error(`vuln-report: npm audit failed (${code}): ${summary}${detail ? `\n${detail}` : ""}`);
    process.exit(2);
  }

  const { text, exitCode } = buildReport(auditReport);
  console.log(text);
  process.exit(exitCode);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main();
}

export { buildReport, describeAction, rankRows, toRow };
