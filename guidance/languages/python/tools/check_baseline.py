#!/usr/bin/env python3
"""Check whether a project has adopted the dev-qual ruff baseline.

Looks for `extend = "…ruff-baseline.toml"` in the project's `pyproject.toml`
(`[tool.ruff]` table) or in a top-level `ruff.toml` / `.ruff.toml`. Prints a
PASS line and exits 0 when adopted; otherwise prints the exact lines to add
and exits 1. Exits 0 with "not a python project" when the directory has none
of `pyproject.toml`, `setup.py`, `requirements.txt`. Exits 2 on a TOML parse
error.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import tomllib

BASELINE_NAME = "ruff-baseline.toml"
BASELINE_PATH = Path(__file__).resolve().parent / BASELINE_NAME


def is_python_project(project: Path) -> bool:
    """Report whether `project` looks like a Python project at all."""
    return any(
        (project / name).is_file()
        for name in ("pyproject.toml", "setup.py", "requirements.txt")
    )


def load_toml(path: Path) -> dict[str, object]:
    """Parse a TOML file, raising `tomllib.TOMLDecodeError` on bad syntax."""
    with path.open("rb") as handle:
        return tomllib.load(handle)


def extend_names_baseline(extend: object) -> bool:
    """Report whether an `extend` value (str or list of str) names the baseline."""
    values = extend if isinstance(extend, list) else [extend]
    return any(
        isinstance(value, str) and Path(value).name == BASELINE_NAME for value in values
    )


def pyproject_adopts_baseline(pyproject: Path) -> bool:
    """Report whether pyproject.toml's [tool.ruff] table extends the baseline."""
    data = load_toml(pyproject)
    tool = data.get("tool")
    if not isinstance(tool, dict):
        return False
    ruff = tool.get("ruff")
    if not isinstance(ruff, dict):
        return False
    return extend_names_baseline(ruff.get("extend"))


def ruff_toml_adopts_baseline(ruff_toml: Path) -> bool:
    """Report whether a ruff.toml / .ruff.toml top-level `extend` names the baseline."""
    data = load_toml(ruff_toml)
    return extend_names_baseline(data.get("extend"))


def baseline_path_for(project: Path) -> str:
    """Return the path from `project` to the baseline file: relative if nested, else absolute."""
    try:
        return str(BASELINE_PATH.relative_to(project.resolve()))
    except ValueError:
        return str(BASELINE_PATH)


def find_ruff_toml(project: Path) -> Path | None:
    """Return the project's ruff.toml or .ruff.toml, preferring ruff.toml."""
    for name in ("ruff.toml", ".ruff.toml"):
        candidate = project / name
        if candidate.is_file():
            return candidate
    return None


def suggestion_for(project: Path) -> str:
    """Build the exact lines to add so the project adopts the baseline."""
    path = baseline_path_for(project)
    ruff_toml = find_ruff_toml(project)
    if ruff_toml is not None:
        return f'Add to {ruff_toml.name}:\n\nextend = "{path}"\n'
    return f'Add to pyproject.toml:\n\n[tool.ruff]\nextend = "{path}"\n'


def check(project: Path) -> int:
    """Check baseline adoption for `project` and print the result. Returns the exit code."""
    if not is_python_project(project):
        print("not a python project")
        return 0

    pyproject = project / "pyproject.toml"
    ruff_toml = find_ruff_toml(project)

    try:
        if pyproject.is_file() and pyproject_adopts_baseline(pyproject):
            print(f"baseline: adopted ({pyproject.name})")
            return 0
        if ruff_toml is not None and ruff_toml_adopts_baseline(ruff_toml):
            print(f"baseline: adopted ({ruff_toml.name})")
            return 0
    except tomllib.TOMLDecodeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    print("baseline: not adopted")
    print(suggestion_for(project))
    return 1


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse command-line arguments for check_baseline."""
    parser = argparse.ArgumentParser(
        description="Check whether a project has adopted the dev-qual ruff baseline."
    )
    parser.add_argument(
        "--project",
        type=Path,
        default=Path.cwd(),
        help="project directory to check (default: current directory)",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    """Run check_baseline as a CLI tool."""
    args = parse_args(argv)
    return check(args.project)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
