#!/usr/bin/env python3
"""Keeps the config skill's checker in step with the app's parser.

The documented example in docs/architecture.md must pass skills/hyperpoint-config/scripts/check_config.py, and every
invalid file in Tests/HyperpointKitTests/ConfigCodecTests.swift must be rejected at the path the Swift test expects.
Run it from the repository root after changing ConfigCodec.
"""

import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("check_config", ROOT / "skills/hyperpoint-config/scripts/check_config.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def documented_example():
    text = (ROOT / "docs/architecture.md").read_text()
    start = text.index("```json\n") + len("```json\n")
    return text[start:text.index("\n```", start)]


def swift_string(literal):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), literal)


def mutations():
    """(find, replace, path) for each Mutation in the Swift test, joining literals split with +."""
    text = (ROOT / "Tests/HyperpointKitTests/ConfigCodecTests.swift").read_text()
    block = text[text.index("static let mutations"):text.index("@Test(arguments: mutations)")]
    for match in re.finditer(r"Mutation\((.*?)\)(?=,\s*(?:Mutation|\]))", block, re.S):
        parts = re.split(r"\b(find|replace|path):", match.group(1))
        fields = {
            label: "".join(swift_string(s) for s in re.findall(r'"((?:[^"\\]|\\.)*)"', segment))
            for label, segment in zip(parts[1::2], parts[2::2])
        }
        yield fields["find"], fields["replace"], fields["path"]


def main():
    example = documented_example()
    failures = []
    for name, text in [("documented example", example),
                       ("chord aliases", example.replace('"shift+cmd+4"', '"Command+Shift+4"'))]:
        try:
            checker.check(text)
        except checker.Problem as problem:
            failures.append(f"{name} is rejected: {problem}")
    cases = list(mutations())
    for find, replace, path in cases:
        if find not in example:
            failures.append(f"mutation for {path!r} does not apply to the documented example")
            continue
        try:
            checker.check(example.replace(find, replace))
            failures.append(f"accepted, but the app rejects it at {path!r}: {replace[:60]}")
        except checker.Problem as problem:
            if problem.path != path:
                failures.append(f"rejected at {problem.path!r}, the app at {path!r} ({problem.message})")
    for failure in failures:
        print(failure)
    print(f"{len(cases)} invalid files and 2 valid ones checked, {len(failures)} disagreements")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
