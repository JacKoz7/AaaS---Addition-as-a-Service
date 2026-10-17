# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/service-api.py
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Generates the events section of every service API.md from
#                  the topic registry and the event schemas, and checks that
#                  the committed sections are up to date (--check).
# Related Docs:    ADR-0013, CLAUDE.md (6.5.5, API.md "generated"),
#                  contracts/events/README.md, Makefile (api-md,
#                  contracts-check)
"""Service API reference generator (command-line tool).

Summary:
    Renders the events produced and consumed by each service into its API.md.

Description:
    ``CLAUDE.md`` 6.5.5 requires ``docs/API.md`` of every service to be
    generated, not edited by hand. This tool owns the part derived from the
    event contracts: in every ``services/*/docs/API.md`` and
    ``frontend/*/docs/API.md`` that contains the markers
    ``<!-- BEGIN GENERATED: events -->`` and ``<!-- END GENERATED: events -->``,
    the text between them is replaced by:

    - the topics whose producer (``contracts/events/topics.psv``) is the
      component, with partitions, message key, schema link and payload fields;
    - the topics whose consumers list the component, with the same details.

    The component name is the directory name. Without ``--check`` the files
    are rewritten; with ``--check`` nothing is written and the exit code is 1
    when a section differs from what would be generated. The HTTP and gRPC
    sections stay hand-maintained until their contracts exist (OpenAPI P2.2,
    proto P2.1).

Business Justification:
    A service's published contract must match the registry that creates the
    topics and the schemas that validate the events; generating the section
    makes drift impossible to commit unnoticed.

Owner: Platform Enablement Guild (PEG)
Since: service-api 0.1.0
Versions: 0.1.0 (P1.4) events section.
See Also: scripts/validate-events.py, scripts/docs-portal.py, ADR-0013.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

#: Marker opening the generated events section.
BEGIN = "<!-- BEGIN GENERATED: events (scripts/service-api.py, do not edit) -->"

#: Marker closing the generated events section.
END = "<!-- END GENERATED: events -->"


def read_registry(root: Path) -> list[list[str]]:
    """Read the topic registry.

    Summary:
        Returns the rows of ``contracts/events/topics.psv``.

    Description:
        Blank lines and ``#`` comments are skipped; each row is split into
        its five columns ``topic|partitions|producer|consumers|purpose``.

    Business Justification:
        The registry names the producer and consumers of every topic.

    Parameters:
        root (Path): repository root.

    Returns:
        list[list[str]]: one row of five strings per topic, in file order.

    Errors:
        OSError: the registry cannot be read.
        ValueError: a row does not have five columns.

    Side Effects:
        Reads one file.

    Complexity: O(n) time and memory in the number of rows.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> read_registry(Path(__file__).resolve().parent.parent)[0][0]
        'aaas.key.pressed.v1'

    See Also: consumers_of.
    """
    rows = []
    for line in (root / "contracts" / "events" / "topics.psv").read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        columns = line.split("|")
        if len(columns) != 5:
            raise ValueError(f"topics.psv: expected 5 columns: {line}")
        rows.append(columns)
    return rows


def consumers_of(row: list[str]) -> list[str]:
    """Extract the consuming components of a registry row.

    Summary:
        Splits the consumers column into component names.

    Description:
        The column lists names separated by commas; text in parentheses (for
        example ``(audit)`` or a step note) is not a component and is removed.

    Business Justification:
        Lets the generator find the topics a component consumes.

    Parameters:
        row (list[str]): registry row.

    Returns:
        list[str]: component names, possibly empty.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(n) in the column length.
    Thread Safety: safe (pure function).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> consumers_of(["t", "3", "p", "parser, stopwatch (from P8.16)", "x"])
        ['parser', 'stopwatch']
        >>> consumers_of(["t", "3", "p", "(audit)", "x"])
        []

    See Also: read_registry.
    """
    text, depth, kept = row[3], 0, []
    for char in text:
        if char == "(":
            depth += 1
        elif char == ")":
            depth = max(0, depth - 1)
        elif depth == 0:
            kept.append(char)
    return [name.strip() for name in "".join(kept).split(",") if name.strip()]


def field_rows(schema: dict[str, Any]) -> list[str]:
    """Render the payload fields of an event schema as table rows.

    Summary:
        One Markdown row per payload property: name, required, description.

    Description:
        Reads ``properties.payload`` of the event schema. Pipes in
        descriptions are escaped; descriptions are kept verbatim otherwise.

    Business Justification:
        Every field of every event is documented in the service reference.

    Parameters:
        schema (dict[str, Any]): parsed event schema.

    Returns:
        list[str]: Markdown table rows.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(n) in the number of fields.
    Thread Safety: safe (pure function).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> s = {"properties": {"payload": {"required": ["a"], "properties": {"a": {"description": "x|y"}}}}}
        >>> field_rows(s)
        ['| `a` | yes | x\\\\|y |']

    See Also: render_topic.
    """
    payload = schema.get("properties", {}).get("payload", {})
    required = set(payload.get("required", []))
    rows = []
    for name, node in payload.get("properties", {}).items():
        description = str(node.get("description", "—")).replace("|", "\\|")
        rows.append(f"| `{name}` | {'yes' if name in required else 'no'} | {description} |")
    return rows


def render_topic(root: Path, row: list[str], direction: str) -> str:
    """Render one topic of a component.

    Summary:
        Markdown subsection for one produced or consumed topic.

    Description:
        Shows the purpose, partitions, message key, the schema link (or a
        note that the schema does not exist yet) and the payload fields. The
        key is ``sessionId`` for an event whose schema fixes ``taskId`` to
        null and ``taskId`` otherwise (CLAUDE.md 4.2, ADR-0013).

    Business Justification:
        The service reference shows exactly what goes over the bus.

    Parameters:
        root (Path): repository root.
        row (list[str]): registry row of the topic.
        direction (str): ``produced`` or ``consumed``.

    Returns:
        str: Markdown text ending with a blank line.

    Errors:
        OSError: a schema exists but cannot be read.
        ValueError: a schema is not valid JSON.

    Side Effects:
        Reads one schema file.

    Complexity: O(schema size).
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> row = read_registry(Path(__file__).resolve().parent.parent)[0]
        >>> render_topic(Path(__file__).resolve().parent.parent, row, "produced").splitlines()[0]
        '### `aaas.key.pressed.v1` (produced)'

    See Also: render_section, field_rows.
    """
    topic, partitions, producer, _, purpose = row
    path = root / "contracts" / "events" / f"{topic}.schema.json"
    schema = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
    # Events without a task (taskId fixed to null) are keyed by session (ADR-0013).
    without_task = schema.get("properties", {}).get("taskId", {}).get("type") == "null"
    key = "`sessionId`" if without_task else "`taskId`"
    text = f"### `{topic}` ({direction})\n\n{purpose}\n\n"
    text += f"- Producer: `{producer}`; partitions: {partitions}; message key: {key}.\n"
    if not schema:
        return text + "- Schema: not defined yet (added by the step that introduces the event).\n\n"
    text += f"- Schema: [`{path.name}`](../../../contracts/events/{path.name}) (`{schema.get('$id', '')}`), "
    text += "in the envelope of `CLAUDE.md` 4.2.\n\n"
    text += "| Payload field | Required | Description |\n| --- | --- | --- |\n"
    return text + "\n".join(field_rows(schema)) + "\n\n"


def render_section(root: Path, component: str) -> str:
    """Render the generated events section of a component.

    Summary:
        Produced topics, then consumed topics, or a statement that there are none.

    Description:
        The text placed between the markers, without the markers.

    Business Justification:
        See the module documentation.

    Parameters:
        root (Path): repository root.
        component (str): component name (directory name).

    Returns:
        str: Markdown text.

    Errors:
        OSError, ValueError: as read_registry and render_topic.

    Side Effects:
        Reads the registry and schemas.

    Complexity: O(registry size + schema sizes).
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> "neither produces nor consumes" in render_section(Path(__file__).resolve().parent.parent, "gateway")
        True

    See Also: update.
    """
    rows = read_registry(root)
    produced = [r for r in rows if r[2] == component]
    consumed = [r for r in rows if component in consumers_of(r)]
    if not produced and not consumed:
        return f"\n`{component}` neither produces nor consumes events.\n\n"
    text = "\n"
    text += "".join(render_topic(root, r, "produced") for r in produced)
    text += "".join(render_topic(root, r, "consumed") for r in consumed)
    return text


def update(root: Path, check: bool) -> list[str]:
    """Regenerate (or check) the events section of every component API.md.

    Summary:
        Applies render_section to every API.md with markers.

    Description:
        Files without both markers are skipped. In check mode nothing is
        written.

    Business Justification:
        One command for ``make api-md`` and one for ``make contracts-check``.

    Parameters:
        root (Path): repository root.
        check (bool): report differences instead of writing.

    Returns:
        list[str]: repository-relative paths that were (or would be) changed.

    Errors:
        OSError, ValueError: as render_section; ValueError also when the END
        marker precedes the BEGIN marker.

    Side Effects:
        Reads every component API.md; writes the changed ones unless ``check``.

    Complexity: O(total size of the files).
    Thread Safety: not safe (writes files).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> update(Path(__file__).resolve().parent.parent, check=True)
        []

    See Also: main.
    """
    changed = []
    for api in sorted([*root.glob("services/*/docs/API.md"), *root.glob("frontend/*/docs/API.md")]):
        text = api.read_text(encoding="utf-8")
        if BEGIN not in text or END not in text:
            continue
        start, end = text.index(BEGIN) + len(BEGIN), text.index(END)
        if end < start:
            raise ValueError(f"{api}: the END marker precedes the BEGIN marker")
        updated = text[:start] + render_section(root, api.parent.parent.name) + text[end:]
        if updated != text:
            changed.append(api.relative_to(root).as_posix())
            if not check:
                api.write_text(updated, encoding="utf-8")
    return changed


def main(argv: list[str]) -> int:
    """Run the generator from the command line.

    Summary:
        ``service-api.py [--check]``.

    Description:
        Prints the changed (or stale) files; in check mode returns 1 when any
        file is stale.

    Business Justification:
        Clear exit codes for CI and developers.

    Parameters:
        argv (list[str]): command-line arguments without the program name.

    Returns:
        int: 0 on success, 1 when ``--check`` finds stale files, 2 on usage errors.

    Errors:
        OSError, ValueError: propagated from update.

    Side Effects:
        As update; writes to stdout and stderr.

    Complexity: as update.
    Thread Safety: not applicable (process entry point).
    Owner: Platform Enablement Guild (PEG)
    Since: service-api 0.1.0

    Example:
        >>> import contextlib, io
        >>> with contextlib.redirect_stdout(io.StringIO()):
        ...     code = main(["--check"])
        >>> code
        0

    See Also: update.
    """
    if argv not in ([], ["--check"]):
        print("usage: service-api.py [--check]", file=sys.stderr)
        return 2
    check = argv == ["--check"]
    print("==> generated events sections of API.md" + (" (check)" if check else ""))
    changed = update(Path(__file__).resolve().parent.parent, check)
    for path in changed:
        print(f"    {'stale' if check else 'updated'}: {path}", file=sys.stderr if check else sys.stdout)
    if check and changed:
        print("error: run `make api-md` and commit the result", file=sys.stderr)
        return 1
    print("    up to date" if not changed else f"    {len(changed)} file(s) updated")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
