#!/usr/bin/env python3

from __future__ import annotations

import argparse
import pathlib
import xml.etree.ElementTree as ET
from collections import defaultdict


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a Cobertura coverage report as GitHub summary markdown."
    )
    parser.add_argument("xml_path", type=pathlib.Path)
    parser.add_argument(
        "--repo-root",
        type=pathlib.Path,
        default=pathlib.Path.cwd(),
        help="Repository root used to normalize file paths.",
    )
    return parser.parse_args()


def format_pct(hit_lines: int, total_lines: int) -> str:
    if total_lines == 0:
        return "0.0%"
    return f"{(100.0 * hit_lines / total_lines):.1f}%"


def sort_rows(rows: list[dict[str, object]]) -> list[dict[str, object]]:
    return sorted(
        rows,
        key=lambda row: (
            float(row["percent"]),
            -int(row["total_lines"]),
            str(row["name"]),
        ),
    )


def render_table(rows: list[dict[str, object]]) -> list[str]:
    lines = [
        "| Name | Coverage | Hit lines | Total lines |",
        "| --- | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            f"| {row['name']} | {row['percent']:.1f}% | "
            f"{row['hit_lines']} | {row['total_lines']} |"
        )
    return lines


def render_uncovered_table(rows: list[dict[str, object]]) -> list[str]:
    lines = [
        "| File | Coverage | Uncovered lines |",
        "| --- | ---: | --- |",
    ]
    for row in rows:
        lines.append(
            f"| {row['name']} | {row['percent']:.1f}% | {row['uncovered_ranges']} |"
        )
    return lines


def parse_hits(raw_hits: str | None) -> int:
    try:
        return int(raw_hits or "0")
    except ValueError:
        return 0


def parse_line_number(raw_number: str | None) -> int | None:
    try:
        return int(raw_number or "")
    except ValueError:
        return None


def collapse_ranges(line_numbers: list[int]) -> str:
    if not line_numbers:
        return ""

    ranges: list[str] = []
    start = line_numbers[0]
    end = line_numbers[0]

    for line_number in line_numbers[1:]:
        if line_number == end + 1:
            end = line_number
            continue
        ranges.append(f"{start}-{end}" if start != end else str(start))
        start = line_number
        end = line_number

    ranges.append(f"{start}-{end}" if start != end else str(start))
    return ", ".join(ranges)


def sort_uncovered_rows(rows: list[dict[str, object]]) -> list[dict[str, object]]:
    return sorted(
        rows,
        key=lambda row: (
            -int(row["uncovered_count"]),
            float(row["percent"]),
            str(row["name"]),
        ),
    )


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    root = ET.parse(args.xml_path).getroot()

    overall_hit_lines = 0
    overall_total_lines = 0
    package_totals: dict[str, dict[str, int]] = defaultdict(
        lambda: {"hit_lines": 0, "total_lines": 0}
    )
    function_rows: dict[str, list[dict[str, object]]] = defaultdict(list)
    other_rows: list[dict[str, object]] = []
    uncovered_rows: list[dict[str, object]] = []

    for class_node in root.findall(".//class"):
        filename = class_node.get("filename")
        if not filename:
            continue

        file_path = pathlib.Path(filename)
        if not file_path.is_absolute():
            file_path = (repo_root / file_path).resolve()

        try:
            relative_path = file_path.relative_to(repo_root)
        except ValueError:
            relative_path = pathlib.Path(filename)

        line_nodes = class_node.findall("./lines/line")
        total_lines = len(line_nodes)
        uncovered_lines = sorted(
            line_number
            for line_node in line_nodes
            for line_number in [parse_line_number(line_node.get("number"))]
            if line_number is not None and parse_hits(line_node.get("hits")) == 0
        )
        hit_lines = total_lines - len(uncovered_lines)

        if total_lines == 0:
            continue

        overall_hit_lines += hit_lines
        overall_total_lines += total_lines

        row = {
            "name": relative_path.as_posix(),
            "hit_lines": hit_lines,
            "total_lines": total_lines,
            "percent": 100.0 * hit_lines / total_lines,
        }

        if uncovered_lines:
            uncovered_rows.append(
                {
                    "name": row["name"],
                    "percent": row["percent"],
                    "uncovered_count": len(uncovered_lines),
                    "uncovered_ranges": collapse_ranges(uncovered_lines),
                }
            )

        parts = relative_path.parts
        if len(parts) >= 3 and parts[0] == "src" and parts[1] == "packages":
            package_name = parts[2]
            package_totals[package_name]["hit_lines"] += hit_lines
            package_totals[package_name]["total_lines"] += total_lines
            function_rows[package_name].append(
                {
                    "name": relative_path.stem,
                    "hit_lines": hit_lines,
                    "total_lines": total_lines,
                    "percent": row["percent"],
                }
            )
        else:
            other_rows.append(row)

    package_rows = []
    for package_name, totals in package_totals.items():
        total_lines = totals["total_lines"]
        hit_lines = totals["hit_lines"]
        package_rows.append(
            {
                "name": package_name,
                "hit_lines": hit_lines,
                "total_lines": total_lines,
                "percent": 100.0 * hit_lines / total_lines if total_lines else 0.0,
            }
        )

    markdown: list[str] = [
        "# Test coverage report",
        "",
        "Coverage combines the instrumented unit test suite and golden test suite.",
        "",
        "## Overall coverage",
        "",
        f"- **All instrumented source files:** {format_pct(overall_hit_lines, overall_total_lines)} "
        f"({overall_hit_lines}/{overall_total_lines} hit lines)",
        f"- **Function packages:** {format_pct(sum(row['hit_lines'] for row in package_rows), sum(row['total_lines'] for row in package_rows))} "
        f"({sum(row['hit_lines'] for row in package_rows)}/{sum(row['total_lines'] for row in package_rows)} hit lines)",
    ]

    if package_rows:
        markdown.extend(["", "## Coverage by package", ""])
        markdown.extend(render_table(sort_rows(package_rows)))

    if function_rows:
        markdown.extend(["", "## Coverage by function", ""])
        for package_name in sorted(function_rows):
            markdown.extend([f"<details><summary><strong>{package_name}</strong></summary>", ""])
            markdown.extend(render_table(sort_rows(function_rows[package_name])))
            markdown.extend(["", "</details>", ""])

    if other_rows:
        markdown.extend(["## Other source modules", ""])
        markdown.extend(render_table(sort_rows(other_rows)))

    if uncovered_rows:
        markdown.extend(["", "## Uncovered instrumented lines", ""])
        markdown.extend(render_uncovered_table(sort_uncovered_rows(uncovered_rows)))

    print("\n".join(markdown).rstrip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
