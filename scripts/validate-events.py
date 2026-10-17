# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/validate-events.py
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Contract test of the event schemas in contracts/events/:
#                  checks every schema against JSON Schema 2020-12 and the
#                  AaaS conventions, requires every valid example to pass and
#                  every invalid example to fail at the expected location,
#                  and verifies the arithmetic and the hash chain of the
#                  examples. Runs in `make contracts-check` and in CI. With
#                  --events, validates events produced by a service's tests
#                  instead.
# Related Docs:    ADR-0013, CLAUDE.md (4.2, 6.4), contracts/events/README.md,
#                  contracts/events/topics.psv
"""Event contract validator (command-line tool).

Summary:
    Validates the JSON Schemas of ``contracts/events/`` and their examples.

Description:
    The event contracts consist of the envelope schema
    (``envelope.v1.schema.json``), one schema per event
    (``<topic>.schema.json``) and examples under
    ``examples/<topic>/valid/*.json`` (raw events) and
    ``examples/<topic>/invalid/*.json`` (test cases of the form
    ``{"description", "errorAt", "event"}``). The tool checks, in order:

    1. every schema is a valid JSON Schema 2020-12 document;
    2. the AaaS conventions of ADR-0013: ``$id``, ``title`` and
       ``description`` are present, an event schema is named after its
       topic, the topic is registered in ``topics.psv`` with the same
       producer, ``type`` and ``version`` match the topic, the schema
       references the envelope, and every property has a ``description``;
    3. every event schema has at least one valid and one invalid example,
       and no example directory exists without a schema;
    4. every valid example passes and carries truthful data: an addition
       result equals ``a + b`` and a ledger hash follows the rule of
       ADR-0013 (native ``+`` is allowed here: this is test tooling, not the
       calculation, CLAUDE.md section 1, rule 5);
    5. every invalid example fails, with at least one error at the JSON
       pointer given in ``errorAt``, so that it cannot pass the test by
       failing for an unintended reason.

    The ``date-time`` format is asserted (``FormatChecker``), so an
    impossible date such as 30 February is rejected. All problems are
    reported before the tool exits.

    With ``--events FILE...`` the tool instead validates events written by
    the unit tests of a producer (for example the parser, ADR-0015): each
    file must pass the schema of the topic named by its ``type`` and
    ``version`` and tell the truth as in check 4.

Business Justification:
    CLAUDE.md 6.4 requires contract tests that validate the example events
    in CI. A schema that silently accepts a malformed event would let an
    invalid addition travel through 35 services before anyone noticed.

Owner: Platform Enablement Guild (PEG)
Since: validate-events 0.1.0
Versions: 0.1.0 (P1.3) first release; 0.2.0 (P1.5) ``--events`` mode.
See Also: ADR-0013, Makefile target ``contracts-check``, scripts/docs-portal.py.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker
from jsonschema.exceptions import best_match
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

#: Directory of the event contracts, relative to the repository root.
EVENTS_DIR = Path("contracts/events")

#: File name of the envelope schema.
ENVELOPE_FILE = "envelope.v1.schema.json"

#: ``$id`` of the envelope schema, referenced by every event schema.
ENVELOPE_ID = "urn:aaas:events:envelope:v1"

#: Suffix of every schema file.
SCHEMA_SUFFIX = ".schema.json"

#: ``prevHash`` of the first entry of the ledger hash chain.
GENESIS_HASH = "0" * 64


def load_json(path: Path) -> Any:
    """Read a JSON document.

    Summary:
        Parses one UTF-8 JSON file.

    Description:
        Thin wrapper that keeps the encoding explicit.

    Business Justification:
        Every contract file is JSON; one reader keeps error handling uniform.

    Parameters:
        path (Path): file to read.

    Returns:
        Any: the parsed document.

    Errors:
        OSError: the file cannot be read.
        ValueError: the file is not valid JSON (``json.JSONDecodeError``).

    Side Effects:
        Reads one file.

    Complexity: O(n) time and memory in the file size.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: validate-events 0.1.0

    Example:
        >>> root = Path(__file__).resolve().parent.parent
        >>> load_json(root / EVENTS_DIR / ENVELOPE_FILE)["$id"]
        'urn:aaas:events:envelope:v1'

    See Also: load_schemas.
    """
    return json.loads(path.read_text(encoding="utf-8"))


def read_producers(events_dir: Path) -> dict[str, str]:
    """Read the producer of every registered topic.

    Summary:
        Maps each topic of ``topics.psv`` to its producer column.

    Description:
        Blank lines and ``#`` comments are skipped; the registry format is
        validated by ``infra/redpanda/create-topics.sh``, so a line with too
        few columns is simply ignored here.

    Business Justification:
        The topic registry names the only service allowed to publish a
        topic; the schema must agree with it.

    Parameters:
        events_dir (Path): the ``contracts/events`` directory.

    Returns:
        dict[str, str]: topic name to producer.

    Errors:
        OSError: the registry cannot be read.

    Side Effects:
        Reads one file.

    Complexity: O(n) time and memory in the number of rows.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: validate-events 0.1.0

    Example:
        >>> root = Path(__file__).resolve().parent.parent
        >>> read_producers(root / EVENTS_DIR)["aaas.addition.requested.v1"]
        'parser'

    See Also: contracts/events/topics.psv.
    """
    producers: dict[str, str] = {}
    for line in (events_dir / "topics.psv").read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        columns = line.split("|")
        if len(columns) >= 3:
            producers[columns[0]] = columns[2]
    return producers


def property_descriptions(node: Any, pointer: str = "") -> list[str]:
    """Find properties without a description.

    Summary:
        Lists the JSON pointers of schema properties lacking ``description``.

    Description:
        Walks the schema recursively; every member of a ``properties``
        object must carry a ``description`` (documentation coverage of the
        contracts, CLAUDE.md 6.5).

    Business Justification:
        Every field of every event is documented, like every function.

    Parameters:
        node (Any): schema or sub-schema.
        pointer (str): JSON pointer of ``node`` inside the schema.

    Returns:
        list[str]: pointers of undocumented properties, empty when complete.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(n) time and O(d) stack in the schema size and depth.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: validate-events 0.1.0

    Example:
        >>> property_descriptions({"properties": {"a": {"description": "x"}, "b": {}}})
        ['/properties/b']

    See Also: check_schema.
    """
    missing: list[str] = []
    if isinstance(node, dict):
        for key, value in node.items():
            child = f"{pointer}/{key}"
            if key == "properties" and isinstance(value, dict):
                missing += [f"{child}/{name}" for name, sub in value.items() if "description" not in sub]
            missing += property_descriptions(value, child)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            missing += property_descriptions(value, f"{pointer}/{index}")
    return missing


def check_schema(name: str, schema: dict[str, Any], producers: dict[str, str]) -> list[str]:
    """Check one schema against JSON Schema and the AaaS conventions.

    Summary:
        Returns the convention violations of one schema file.

    Description:
        Applies the meta-schema of draft 2020-12 and the rules of ADR-0013
        listed in the module docstring (step 2). The envelope is exempt from
        the topic rules.

    Business Justification:
        Uniform schemas let producers, consumers, the schema registry (P3.1)
        and the portal treat every event the same way.

    Parameters:
        name (str): file name, used in messages and to derive the topic.
        schema (dict[str, Any]): parsed schema.
        producers (dict[str, str]): topic registry, from read_producers.

    Returns:
        list[str]: problems, empty when the schema is compliant.

    Errors:
        None (problems are returned).

    Side Effects:
        None.

    Complexity: O(n) time and memory in the schema size.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: validate-events 0.1.0

    Example:
        >>> check_schema("x.schema.json", {"type": 3}, {})[0].startswith("x.schema.json: not a valid")
        True

    See Also: property_descriptions, read_producers.
    """
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as error:  # SchemaError, or an invalid regular expression
        return [f"{name}: not a valid JSON Schema 2020-12 document: {getattr(error, 'message', error)}"]
    problems = [f"{name}: missing '{key}'" for key in ("$id", "title", "description") if key not in schema]
    problems += [f"{name}: property {p} has no description" for p in property_descriptions(schema)]
    if name == ENVELOPE_FILE:
        if schema.get("$id") != ENVELOPE_ID:
            problems.append(f"{name}: $id must be {ENVELOPE_ID}")
        return problems
    topic = name.removesuffix(SCHEMA_SUFFIX)
    props = schema.get("properties", {})
    event_type, _, version = topic.rpartition(".v")
    expected = {
        "title": (schema.get("title"), topic),
        "$id": (schema.get("$id"), f"urn:aaas:events:{topic}"),
        "type": (props.get("type", {}).get("const"), event_type),
        "version": (props.get("version", {}).get("const"), int(version) if version.isdigit() else None),
        "producer": (props.get("producer", {}).get("const"), producers.get(topic)),
    }
    if topic not in producers:
        problems.append(f"{name}: topic {topic} is not registered in topics.psv")
    problems += [f"{name}: {key} is {got!r}, expected {want!r}" for key, (got, want) in expected.items() if got != want]
    if {"$ref": ENVELOPE_ID} not in schema.get("allOf", []):
        problems.append(f"{name}: allOf must reference the envelope {ENVELOPE_ID}")
    return problems


def check_truth(event: dict[str, Any]) -> list[str]:
    """Check the arithmetic and the hash chain of a valid example.

    Summary:
        Verifies that a valid example tells the truth.

    Description:
        A payload with ``a``, ``b`` and ``result`` must satisfy
        ``result == a + b``. A payload with ``hash`` must carry the SHA-256
        of ``prevHash|taskId|a|b|result|recordedAt`` (ADR-0013), and the
        entry with ``sequence`` 1 must have the genesis ``prevHash``.

    Business Justification:
        Examples are reused as fixtures by services; a wrong sum or hash in
        a fixture would teach a service the wrong behaviour.

    Parameters:
        event (dict[str, Any]): an example that already passed its schema.

    Returns:
        list[str]: problems, empty when the example is truthful.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(1) time and memory.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: validate-events 0.1.0

    Example:
        >>> check_truth({"taskId": "t", "payload": {"a": 2, "b": 3, "result": 6}})
        ['result 6 is not 2 + 3']

    See Also: ledger_hash.
    """
    payload = event.get("payload", {})
    problems = []
    if {"a", "b", "result"} <= payload.keys() and payload["result"] != payload["a"] + payload["b"]:
        problems.append(f"result {payload['result']} is not {payload['a']} + {payload['b']}")
    if "hash" in payload:
        if payload["hash"] != ledger_hash(event["taskId"], payload):
            problems.append("hash does not match prevHash|taskId|a|b|result|recordedAt")
        if payload.get("sequence") == 1 and payload.get("prevHash") != GENESIS_HASH:
            problems.append("the first entry must have the genesis prevHash (64 zeros)")
    return problems


def ledger_hash(task_id: str, entry: dict[str, Any]) -> str:
    """Compute the hash of a ledger entry.

    Summary:
        Applies the hash rule of ADR-0013 to one entry.

    Description:
        ``sha256(UTF-8("prevHash|taskId|a|b|result|recordedAt"))`` in
        lowercase hexadecimal; numbers are rendered in decimal without
        leading zeros, the separator removes the ambiguity of plain
        concatenation (``1|23`` versus ``12|3``).

    Business Justification:
        The ledger, cloud-notary and this test must compute the same hash.

    Parameters:
        task_id (str): taskId of the event.
        entry (dict[str, Any]): payload with prevHash, a, b, result and
            recordedAt.

    Returns:
        str: 64 lowercase hexadecimal characters.

    Errors:
        KeyError: a required field is missing.

    Side Effects:
        None.

    Complexity: O(1) time and memory.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: validate-events 0.1.0

    Example:
        >>> e = {"prevHash": GENESIS_HASH, "a": 3, "b": 2, "result": 5, "recordedAt": "2026-10-16T12:00:02.530Z"}
        >>> len(ledger_hash("018f3c2e-7b1a-7c3d-9f00-0000000000aa", e))
        64

    See Also: check_truth, contracts/events/aaas.ledger.appended.v1.schema.json.
    """
    fields = (entry["prevHash"], task_id, entry["a"], entry["b"], entry["result"], entry["recordedAt"])
    return hashlib.sha256("|".join(str(f) for f in fields).encode("utf-8")).hexdigest()


def error_pointers(validator: Draft202012Validator, event: Any) -> set[str]:
    """Collect the instance locations of all validation errors.

    Summary:
        Returns the JSON pointers at which ``event`` violates the schema.

    Description:
        Includes the locations of nested errors (from ``oneOf``, ``anyOf``
        and ``allOf``) so that the expected location is found even when the
        top-level error is reported at a parent.

    Business Justification:
        Invalid examples must fail for the documented reason only.

    Parameters:
        validator (Draft202012Validator): validator of one event schema.
        event (Any): the instance to validate.

    Returns:
        set[str]: pointers such as ``/payload/a``; ``""`` is the root.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(n) time and memory in the number of errors.
    Thread Safety: safe (validators are immutable).
    Owner: Platform Enablement Guild (PEG)
    Since: validate-events 0.1.0

    Example:
        >>> error_pointers(Draft202012Validator({"properties": {"a": {"type": "integer"}}}), {"a": "x"})
        {'/a'}

    See Also: check_examples.
    """
    pointers: set[str] = set()
    stack = list(validator.iter_errors(event))
    while stack:
        error = stack.pop()
        pointers.add("".join(f"/{part}" for part in error.absolute_path))
        stack.extend(error.context or [])
    return pointers


def check_examples(topic: str, validator: Draft202012Validator, examples: Path) -> tuple[list[str], int]:
    """Validate the examples of one event.

    Summary:
        Runs the valid and invalid examples of one topic.

    Description:
        Steps 3 to 5 of the module docstring for one topic directory.

    Business Justification:
        Positive examples prove the schema accepts real events; negative
        examples prove it rejects the mistakes it exists to catch.

    Parameters:
        topic (str): topic name, used in messages.
        validator (Draft202012Validator): validator of the topic's schema.
        examples (Path): ``examples/<topic>`` directory.

    Returns:
        tuple[list[str], int]: problems found and number of examples run.

    Errors:
        None (unreadable files are reported as problems).

    Side Effects:
        Reads the example files.

    Complexity: O(n) time in the total size of the examples.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: validate-events 0.1.0

    Example:
        >>> problems, count = check_examples("t", Draft202012Validator({}), Path("/nonexistent"))
        >>> problems
        ['t: no valid example in /nonexistent/valid', 't: no invalid example in /nonexistent/invalid']

    See Also: error_pointers, check_truth.
    """
    problems: list[str] = []
    valid = sorted((examples / "valid").glob("*.json"))
    invalid = sorted((examples / "invalid").glob("*.json"))
    problems += [
        f"{topic}: no {kind} example in {examples / kind}"
        for kind, f in (("valid", valid), ("invalid", invalid))
        if not f
    ]
    for path in valid:
        rel = f"{topic}/valid/{path.name}"
        try:
            event = load_json(path)
        except (OSError, ValueError) as error:
            problems.append(f"{rel}: unreadable: {error}")
            continue
        error = best_match(validator.iter_errors(event))
        if error is not None:
            where = "".join(f"/{p}" for p in error.absolute_path) or "/"
            problems.append(f"{rel}: rejected at {where}: {error.message}")
            continue
        problems += [f"{rel}: {p}" for p in check_truth(event)]
    for path in invalid:
        rel = f"{topic}/invalid/{path.name}"
        try:
            case = load_json(path)
        except (OSError, ValueError) as error:
            problems.append(f"{rel}: unreadable: {error}")
            continue
        if not isinstance(case, dict) or not {"description", "errorAt", "event"} <= case.keys():
            problems.append(f"{rel}: a test case needs description, errorAt and event")
            continue
        pointers = error_pointers(validator, case["event"])
        if not pointers:
            problems.append(f"{rel}: accepted, but must be rejected ({case['description']})")
        elif case["errorAt"] not in pointers:
            problems.append(f"{rel}: rejected at {sorted(pointers)}, expected at {case['errorAt']!r}")
    return problems, len(valid) + len(invalid)


def load_schemas(root: Path) -> tuple[dict[str, dict[str, Any]], Registry, list[str]]:
    """Load and check every schema of the repository.

    Summary:
        Reads the schemas of ``contracts/events/`` into one registry.

    Description:
        Checks every schema with ``check_schema`` and requires the envelope.
        The registry resolves the envelope by its ``$id`` from the event
        schemas. When any problem is found the registry is empty.

    Business Justification:
        Shared by the contract check (``validate``) and the validation of
        produced events (``validate_events``).

    Parameters:
        root (Path): repository root.

    Returns:
        tuple[dict[str, dict[str, Any]], Registry, list[str]]: the schemas by
        file name, the registry and the problems found.

    Errors:
        OSError: ``topics.psv`` cannot be read.

    Side Effects:
        Reads the contract files.

    Complexity: O(n) time and memory in the total size of the schemas.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: validate-events 0.2.0

    Example:
        >>> schemas, _, problems = load_schemas(Path(__file__).resolve().parent.parent)
        >>> problems, ENVELOPE_FILE in schemas
        ([], True)

    See Also: validate, validate_events, check_schema.
    """
    events_dir = root / EVENTS_DIR
    producers = read_producers(events_dir)
    schemas: dict[str, dict[str, Any]] = {}
    problems: list[str] = []
    for path in sorted(events_dir.glob(f"*{SCHEMA_SUFFIX}")):
        try:
            schema = load_json(path)
        except (OSError, ValueError) as error:
            problems.append(f"{path.name}: unreadable: {error}")
            continue
        schemas[path.name] = schema
        problems += check_schema(path.name, schema, producers)
    if ENVELOPE_FILE not in schemas:
        problems.append(f"{ENVELOPE_FILE}: missing")
    if problems:
        return schemas, Registry(), problems
    registry = Registry().with_resources(
        (schema["$id"], Resource.from_contents(schema, default_specification=DRAFT202012))
        for schema in schemas.values()
    )
    return schemas, registry, []


def validate_events(root: Path, files: list[Path]) -> list[str]:
    """Validate events produced by a service.

    Summary:
        Checks each event file against the schema of its topic.

    Description:
        The topic of an event is ``<type>.v<version>``; an event whose topic
        has no schema is a problem. Every event must pass its schema (with
        the ``date-time`` format asserted) and the truth check of valid
        examples (``check_truth``). An empty file list is a problem too, so
        that a test that silently produced nothing cannot pass.

    Business Justification:
        Contract test of producers (CLAUDE.md 6.4): an event a service
        really publishes is checked by the same schema as the examples.

    Parameters:
        root (Path): repository root.
        files (list[Path]): JSON files, one event each.

    Returns:
        list[str]: problems, empty when every event is valid.

    Errors:
        OSError: ``topics.psv`` cannot be read.

    Side Effects:
        Reads the contract files and the event files; prints one line per
        file to stdout.

    Complexity: O(n) time and memory in the total size of the files.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: validate-events 0.2.0

    Example:
        >>> import contextlib, io
        >>> root = Path(__file__).resolve().parent.parent
        >>> example = root / EVENTS_DIR / "examples/aaas.addition.requested.v1/valid/claude-md-example.json"
        >>> with contextlib.redirect_stdout(io.StringIO()):
        ...     problems = validate_events(root, [example])
        >>> problems
        []

    See Also: load_schemas, check_truth, main.
    """
    schemas, registry, problems = load_schemas(root)
    if problems:
        return problems
    if not files:
        return ["--events: no event files given"]
    for path in files:
        try:
            event = load_json(path)
        except (OSError, ValueError) as error:
            problems.append(f"{path}: unreadable: {error}")
            continue
        topic = f"{event.get('type')}.v{event.get('version')}" if isinstance(event, dict) else "?"
        schema = schemas.get(f"{topic}{SCHEMA_SUFFIX}")
        if schema is None:
            problems.append(f"{path}: no schema for topic {topic}")
            continue
        validator = Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())
        found = [f"{path}: {error.json_path}: {error.message}" for error in validator.iter_errors(event)]
        if not found:
            found = [f"{path}: {problem}" for problem in check_truth(event)]
        problems += found
        print(f"  {'ok  ' if not found else 'FAIL'} {path.name} ({topic})")
    return problems


def validate(root: Path) -> list[str]:
    """Validate every event contract of the repository.

    Summary:
        Runs all checks and returns every problem found.

    Description:
        Loads all schemas into one ``referencing`` registry
        (``load_schemas``), then checks the examples. Prints one summary line per event schema.

    Business Justification:
        One entry point for ``make contracts-check`` and CI.

    Parameters:
        root (Path): repository root.

    Returns:
        list[str]: problems, empty when every contract is valid.

    Errors:
        OSError: ``topics.psv`` cannot be read.

    Side Effects:
        Reads the contract files; prints progress to stdout.

    Complexity: O(n) time and memory in the total size of the contracts.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: validate-events 0.1.0

    Example:
        >>> import contextlib, io
        >>> with contextlib.redirect_stdout(io.StringIO()):
        ...     problems = validate(Path(__file__).resolve().parent.parent)
        >>> problems
        []

    See Also: main, check_schema, check_examples.
    """
    events_dir = root / EVENTS_DIR
    schemas, registry, problems = load_schemas(root)
    if problems:
        return problems
    topics = sorted(name.removesuffix(SCHEMA_SUFFIX) for name in schemas if name != ENVELOPE_FILE)
    for topic in topics:
        schema = schemas[f"{topic}{SCHEMA_SUFFIX}"]
        validator = Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())
        found, count = check_examples(topic, validator, events_dir / "examples" / topic)
        problems += found
        print(f"  {'ok  ' if not found else 'FAIL'} {topic}: {count} examples")
    orphans = sorted(p.name for p in (events_dir / "examples").glob("*") if p.is_dir() and p.name not in topics)
    problems += [f"examples/{name}: no schema {name}{SCHEMA_SUFFIX}" for name in orphans]
    return problems


def main(argv: list[str] | None = None) -> int:
    """Run the validator from the command line.

    Summary:
        Validates the contracts, or the given produced events.

    Description:
        Without arguments validates the contracts of the repository
        containing this script. With ``--events FILE...`` validates those
        event files instead (``validate_events``). Prints every problem to
        stderr and returns 1 if there is any.

    Business Justification:
        Gives CI and developers one command with a clear exit code.

    Parameters:
        argv (list[str] | None): arguments without the program name;
            ``sys.argv[1:]`` when ``None``.

    Returns:
        int: 0 when everything is valid, 1 on problems, 2 on a usage error.

    Errors:
        OSError: ``topics.psv`` cannot be read (propagated).

    Side Effects:
        Reads the contract files; writes to stdout and stderr.

    Complexity: as validate or validate_events.
    Thread Safety: not applicable (process entry point).
    Owner: Platform Enablement Guild (PEG)
    Since: validate-events 0.1.0

    Example:
        >>> import contextlib, io
        >>> with contextlib.redirect_stdout(io.StringIO()):
        ...     code = main([])
        >>> code
        0

    See Also: validate, validate_events.
    """
    args = sys.argv[1:] if argv is None else argv
    root = Path(__file__).resolve().parent.parent
    if args and args[0] == "--events":
        print("==> produced events")
        sys.stdout.flush()
        problems = validate_events(root, [Path(arg) for arg in args[1:]])
        what = "produced events"
    elif args:
        print("usage: validate-events.py [--events FILE...]", file=sys.stderr)
        return 2
    else:
        print("==> event contracts (contracts/events)")
        sys.stdout.flush()
        problems = validate(root)
        what = "event contracts"
    sys.stdout.flush()
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)
    if problems:
        print(f"{len(problems)} problem(s) in the {what}", file=sys.stderr)
        return 1
    print(f"    all {what} are valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
