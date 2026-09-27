#!/usr/bin/env python3
"""Turn `pip-audit` output into a ranked, actionable vulnerability report.

Runs `pip-audit -f json` against a project (or reads a saved report with
`--input`), then prints one row per vulnerable dependency ranked by whether a
fix exists, then direct-before-transitive, then name.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import TypedDict

import tomllib

DEPENDENCIES_DOC = "guidance/standards/dependencies.md"


class Vuln(TypedDict, total=False):
    """One vulnerability entry as pip-audit reports it."""

    id: str
    fix_versions: list[str]
    aliases: list[str]
    description: str


class Dependency(TypedDict, total=False):
    """One dependency entry as pip-audit reports it."""

    name: str
    version: str
    vulns: list[Vuln]
    skip_reason: str


class Finding(TypedDict):
    """A single vulnerable dependency, ready to rank and print."""

    name: str
    version: str
    vuln_ids: list[str]
    direct: bool
    has_fix: bool
    action: str


def normalize_name(name: str) -> str:
    """Normalise a package name per PEP 503: lowercase, runs of -_. -> -."""
    return re.sub(r"[-_.]+", "-", name).lower()


def version_numbers(version: str) -> tuple[int, ...]:
    """Extract the numeric components of a version string, for comparison."""
    return tuple(int(n) for n in re.findall(r"\d+", version))


def major_version(version: str) -> int:
    """Return the leading numeric component of a version string, or 0."""
    numbers = version_numbers(version)
    return numbers[0] if numbers else 0


def extract_dependency_name(spec: str) -> str | None:
    """Extract the package name from a requirement spec string, if present."""
    match = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", spec.strip())
    return match.group(0) if match else None


def direct_names_from_pyproject(pyproject: Path) -> set[str]:
    """Collect normalised direct dependency names declared in pyproject.toml."""
    with pyproject.open("rb") as handle:
        data = tomllib.load(handle)
    project = data.get("project")
    if not isinstance(project, dict):
        return set()

    specs: list[str] = []
    deps = project.get("dependencies")
    if isinstance(deps, list):
        specs.extend(str(dep) for dep in deps)
    optional = project.get("optional-dependencies")
    if isinstance(optional, dict):
        for group in optional.values():
            if isinstance(group, list):
                specs.extend(str(dep) for dep in group)

    names = set()
    for spec in specs:
        name = extract_dependency_name(spec)
        if name:
            names.add(normalize_name(name))
    return names


def direct_names_from_requirements(project: Path) -> set[str]:
    """Collect normalised direct dependency names from requirements*.txt files."""
    names = set()
    for req_file in project.glob("requirements*.txt"):
        for line in req_file.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith(("#", "-")):
                continue
            name = extract_dependency_name(line)
            if name:
                names.add(normalize_name(name))
    return names


def collect_direct_names(project: Path) -> set[str]:
    """Collect all normalised direct dependency names declared by the project."""
    names = direct_names_from_requirements(project)
    pyproject = project / "pyproject.toml"
    if pyproject.is_file():
        names |= direct_names_from_pyproject(pyproject)
    return names


def build_action(
    name: str, current_version: str, fix_versions: list[str]
) -> tuple[str, bool]:
    """Build the recommended action for a vulnerable dependency. Returns (action, has_fix)."""
    if not fix_versions:
        return f"no fix available — consider replacing (see {DEPENDENCIES_DOC})", False
    lowest_fix = min(fix_versions, key=version_numbers)
    action = f"pip install '{name}>={lowest_fix}'"
    if major_version(lowest_fix) > major_version(current_version):
        action += " (MAJOR — ask the user first)"
    return action, True


def build_findings(
    dependencies: list[Dependency], direct_names: set[str]
) -> list[Finding]:
    """Turn pip-audit's dependency list into ranked findings for vulnerable packages."""
    findings: list[Finding] = []
    for dep in dependencies:
        vulns = dep.get("vulns")
        if not vulns:
            continue
        name = dep["name"]
        version = dep.get("version", "unknown")
        fix_versions = sorted(
            {fv for vuln in vulns for fv in vuln.get("fix_versions", [])}
        )
        action, has_fix = build_action(name, version, fix_versions)
        findings.append(
            Finding(
                name=name,
                version=version,
                vuln_ids=[vuln["id"] for vuln in vulns],
                direct=normalize_name(name) in direct_names,
                has_fix=has_fix,
                action=action,
            )
        )

    findings.sort(key=lambda f: (not f["has_fix"], not f["direct"], f["name"].lower()))
    return findings


def format_row(finding: Finding) -> str:
    """Format one finding as a report row."""
    directness = "direct" if finding["direct"] else "transitive"
    vuln_ids = ",".join(finding["vuln_ids"])
    return f"{finding['name']}  {finding['version']}  {vuln_ids}  {directness}  {finding['action']}"


def format_summary(findings: list[Finding]) -> str:
    """Format the summary line with counts and next-step guidance."""
    total = len(findings)
    direct = sum(1 for f in findings if f["direct"])
    transitive = total - direct
    fixable = sum(1 for f in findings if f["has_fix"])
    return (
        f"{total} vulnerable package(s): {direct} direct, {transitive} transitive, "
        f"{fixable} with a fix available. "
        "Next: update the lockfile/requirements in small groups, security first, "
        "running check.sh after each (skills/deps-audit)"
    )


def run_pip_audit(project: Path) -> str:
    """Run `pip-audit -f json` in `project` and return its stdout."""
    if shutil.which("pip-audit") is None:
        raise FileNotFoundError("pip-audit")
    result = subprocess.run(
        ["pip-audit", "-f", "json"],
        cwd=project,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout


def report(project: Path, input_file: Path | None) -> int:
    """Build and print the vulnerability report. Returns the process exit code."""
    if input_file is not None:
        text = input_file.read_text()
    else:
        try:
            text = run_pip_audit(project)
        except FileNotFoundError:
            print("pip install pip-audit", file=sys.stderr)
            return 2

    try:
        data = json.loads(text)
    except json.JSONDecodeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    dependencies: list[Dependency] = data.get("dependencies", [])
    direct_names = collect_direct_names(project)
    findings = build_findings(dependencies, direct_names)

    if not findings:
        print("no vulnerabilities found")
        return 0

    for finding in findings:
        print(format_row(finding))
    print(format_summary(findings))
    return 1


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse command-line arguments for vuln_report."""
    parser = argparse.ArgumentParser(
        description="Run pip-audit and print a ranked, actionable vulnerability report."
    )
    parser.add_argument(
        "--project",
        type=Path,
        default=Path.cwd(),
        help="project directory to audit (default: current directory)",
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=None,
        help="read a saved `pip-audit -f json` report instead of running pip-audit",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    """Run vuln_report as a CLI tool."""
    args = parse_args(argv)
    return report(args.project, args.input)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
