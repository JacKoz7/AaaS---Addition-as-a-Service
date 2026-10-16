# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/docs-portal.py
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Assembles the sources of the documentation portal into
#                  build/portal/: copies the repository documents, rewrites
#                  their links, and generates the service map, the service,
#                  event, API and changelog catalogs and the ADR, RFC, step
#                  log and release note indexes. Runs as an MkDocs hook
#                  before every build.
# Related Docs:    ADR-0010, ADR-0011, mkdocs.yml, CLAUDE.md (6.5.7),
#                  templates/service/catalog.psv, contracts/events/topics.psv
"""Documentation portal assembler (MkDocs hook and command-line tool).

Summary:
    Builds the MkDocs ``docs_dir`` (``build/portal/``) from the repository.

Description:
    The portal shows documents that live all over the repository (root
    documents, ``docs/``, ``services/*/docs/``, ``frontend/*/docs/``,
    ``contracts/``) and pages generated from machine-readable sources (the
    service catalog, the topic registry, JSON Schemas, OpenAPI and proto files, ADR metadata).
    MkDocs reads a single directory, so this module mirrors the documents
    into ``build/portal/`` under their repository paths, with two
    exceptions: the root ``README.md`` becomes the home page ``index.md``,
    and a link to a file that is not part of the portal is rewritten to the
    file on GitHub. Files are written only when their content changes and
    stale files are removed, so ``mkdocs serve`` does not rebuild in a loop.

    MkDocs loads this file through ``hooks:`` in ``mkdocs.yml`` and calls
    :func:`on_pre_build` before collecting the documentation files. Running
    the file directly (``python3 scripts/docs-portal.py``) assembles the
    portal without building it.

Business Justification:
    CLAUDE.md 6.5.7 requires a single portal with a service map, catalogs,
    ADRs, RFCs, the risk register and changelogs. Stakeholders of an
    enterprise addition platform must find any document in one place.

Owner: Platform Enablement Guild (PEG)
Since: docs-portal 0.1.0
Versions: 0.1.0 (P0.10) first release; 0.2.0 (P1.1) topic registry in the
    event catalog.
See Also: mkdocs.yml, ADR-0010, Makefile targets ``docs`` and ``docs-serve``.
"""

from __future__ import annotations

import json
import logging
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

#: Logger under the ``mkdocs`` namespace so that warnings fail ``--strict``.
LOG = logging.getLogger("mkdocs.hooks.docs_portal")

#: Public repository; targets of links to files outside the portal.
REPO_URL = "https://github.com/JacKoz7/AaaS---Addition-as-a-Service"

#: Branch that GitHub links point to.
REPO_BRANCH = "main"

#: Portal directory, relative to the repository root. The assembler refuses
#: to run against any other ``docs_dir`` because it deletes stale files.
PORTAL_DIR = PurePosixPath("build/portal")

#: Directory in which ``make docs`` collects the native API documentation of
#: every component (``build/api-docs/<component>/index.html``).
API_DOCS_DIR = PurePosixPath("build/api-docs")

#: Root documents mirrored into the portal (CLAUDE.md is Polish and is linked
#: on GitHub instead, so that the portal stays English).
ROOT_DOCUMENTS = ("README.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "SECURITY.md")

#: Root files without a Markdown extension that documents link to; they are
#: copied verbatim and served as plain files.
ROOT_PLAIN_FILES = ("LICENSE", "CODEOWNERS")

#: Extensions of files copied from the document trees besides Markdown.
ASSET_SUFFIXES = (".png", ".svg", ".jpg", ".jpeg", ".gif", ".webp")

#: Service catalog (CLAUDE.md section 2), shared with scripts/new-service.sh.
CATALOG = PurePosixPath("templates/service/catalog.psv")

#: Topic registry (CLAUDE.md 4.2), shared with infra/redpanda/create-topics.sh.
TOPICS = PurePosixPath("contracts/events/topics.psv")

#: Corporate documents of a component (CLAUDE.md 6.5.5), in display order.
COMPONENT_DOCUMENTS = (
    "SERVICE_CHARTER.md",
    "RACI.md",
    "SLO.md",
    "RUNBOOK.md",
    "THREAT_MODEL.md",
    "DATA_CLASSIFICATION.md",
    "DEPENDENCIES.md",
    "CAPACITY.md",
    "API.md",
    "CHANGELOG.md",
)

#: Inline Markdown link or image target: ``](target)`` or ``](<target>)``,
#: optionally followed by a title.
INLINE_LINK = re.compile(r'(\]\()(<[^>]*>|[^)\s]+)((?:\s+"[^"]*")?\))')

#: Reference-style link definition: ``[label]: target``.
REFERENCE_LINK = re.compile(r"^(\s{0,3}\[[^\]]+\]:\s*)(\S+)(.*)$")

#: Inline code span, protected from link rewriting.
CODE_SPAN = re.compile(r"(`+)(?:(?!\1).)+?\1")

#: Fenced code block delimiter.
FENCE = re.compile(r"^\s{0,3}(```+|~~~+)")

#: URL scheme (``https:``, ``mailto:``) of an absolute link.
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


@dataclass(frozen=True)
class Service:
    """One row of the service catalog.

    Summary:
        Immutable record of a service from ``templates/service/catalog.psv``.

    Description:
        Mirrors the columns ``name|language|team|abbr|database|kind|purpose``.
        ``number`` is the 1-based row position, which equals the number of the
        service in CLAUDE.md section 2.

    Business Justification:
        The service map and the service catalog are generated from the same
        rows as the scaffolding script, so the portal cannot disagree with it.

    Parameters:
        number (int): position in CLAUDE.md section 2, 1..35.
        name (str): kebab-case service name.
        language (str): implementation language or technology keyword.
        team (str): owning team (CLAUDE.md 6.5.1).
        abbr (str): team abbreviation, e.g. ``AEC``.
        database (str): database technology.
        kind (str): ``container`` or ``embedded``.
        purpose (str): one-sentence role in the addition.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(1) time and memory per instance.
    Thread Safety: immutable, safe to share.
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> Service(23, "successor", "haskell", "Arithmetic Excellence Center",
        ...         "AEC", "CouchDB", "container", "Computes n+1.").abbr
        'AEC'

    See Also: read_catalog, templates/service/catalog.psv.
    """

    number: int
    name: str
    language: str
    team: str
    abbr: str
    database: str
    kind: str
    purpose: str


class Portal:
    """In-memory model of the portal directory being assembled.

    Summary:
        Collects the files of the portal and writes them to ``build/portal``.

    Description:
        Files are registered with :meth:`add_text` or :meth:`add_copy` under
        their portal path. :meth:`write` then creates or updates only the
        files whose content differs from what is on disk and deletes every
        other file, so the directory always equals the registered set.

    Business Justification:
        Writing only changed files keeps ``mkdocs serve`` from rebuilding in a
        loop, since the server watches the directory this class writes.

    Parameters:
        root (Path): repository root.
        out (Path): portal directory; must be ``<root>/build/portal``.

    Errors:
        ValueError: ``out`` is not ``<root>/build/portal``.

    Side Effects:
        None until :meth:`write` is called.

    Complexity: O(1) to construct.
    Thread Safety: not thread-safe; one instance per build.
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> Portal(Path("/r"), Path("/r/build/portal")).files
        {}

    See Also: assemble.
    """

    def __init__(self, root: Path, out: Path) -> None:
        """Initialise an empty portal.

        Summary:
            Stores the paths and validates the output directory.

        Description:
            The check protects the repository: :meth:`write` deletes every
            file that was not registered, so pointing it at ``docs/`` would
            wipe the documentation.

        Business Justification:
            A documentation tool must never destroy documentation.

        Parameters:
            root (Path): repository root.
            out (Path): portal directory.

        Returns:
            None.

        Errors:
            ValueError: ``out`` resolves to anything but ``<root>/build/portal``.

        Side Effects:
            None.

        Complexity: O(1) time and memory.
        Thread Safety: not applicable (constructor).
        Owner: Platform Enablement Guild (PEG)
        Since: docs-portal 0.1.0

        Example:
            >>> Portal(Path("/r"), Path("/r/docs"))
            Traceback (most recent call last):
            ...
            ValueError: refusing to assemble the portal into /r/docs; expected /r/build/portal

        See Also: PORTAL_DIR.
        """
        expected = root.joinpath(*PORTAL_DIR.parts)
        if Path(os.path.normpath(out)) != Path(os.path.normpath(expected)):
            raise ValueError(f"refusing to assemble the portal into {out}; expected {expected}")
        self.root = root
        self.out = out
        self.files: dict[str, bytes] = {}

    def add_text(self, path: str, text: str) -> None:
        """Register a text file.

        Summary:
            Adds or replaces the file ``path`` with ``text`` (UTF-8).

        Description:
            ``path`` is relative to the portal root and uses ``/``.

        Business Justification:
            Generated catalog pages and rewritten documents are text.

        Parameters:
            path (str): portal-relative POSIX path.
            text (str): file content.

        Returns:
            None.

        Errors:
            None.

        Side Effects:
            None (in memory).

        Complexity: O(n) time and memory in the length of ``text``.
        Thread Safety: not thread-safe.
        Owner: Platform Enablement Guild (PEG)
        Since: docs-portal 0.1.0

        Example:
            >>> p = Portal(Path("/r"), Path("/r/build/portal"))
            >>> p.add_text("index.md", "# Home\\n")
            >>> p.files["index.md"]
            b'# Home\\n'

        See Also: add_copy.
        """
        self.files[path] = text.encode("utf-8")

    def add_copy(self, path: str, source: Path) -> None:
        """Register a verbatim copy of a file.

        Summary:
            Adds the bytes of ``source`` under the portal path ``path``.

        Description:
            Used for images, plain files such as ``LICENSE`` and the native
            API documentation of components.

        Business Justification:
            Documents link to these files; they must be reachable in the portal.

        Parameters:
            path (str): portal-relative POSIX path.
            source (Path): existing file to copy.

        Returns:
            None.

        Errors:
            OSError: ``source`` cannot be read.

        Side Effects:
            Reads ``source``.

        Complexity: O(n) time and memory in the size of ``source``.
        Thread Safety: not thread-safe.
        Owner: Platform Enablement Guild (PEG)
        Since: docs-portal 0.1.0

        Example:
            >>> p = Portal(Path("/r"), Path("/r/build/portal"))
            >>> p.add_copy("LICENSE", Path(__file__))
            >>> "LICENSE" in p.files
            True

        See Also: add_text.
        """
        self.files[path] = source.read_bytes()

    def write(self) -> tuple[int, int]:
        """Synchronise the portal directory with the registered files.

        Summary:
            Writes changed files and deletes unregistered ones.

        Description:
            A file is rewritten only when its bytes differ from the
            registered content. Files and then empty directories that are not
            registered are removed.

        Business Justification:
            Keeps the portal exact and the development server quiet.

        Parameters:
            None.

        Returns:
            tuple[int, int]: number of files written and number removed.

        Errors:
            OSError: a file cannot be written or removed.

        Side Effects:
            Creates, overwrites and deletes files under ``build/portal``.

        Complexity: O(total size of the portal) time, O(largest file) memory.
        Thread Safety: not thread-safe; no other writer may use the directory.
        Owner: Platform Enablement Guild (PEG)
        Since: docs-portal 0.1.0

        Example:
            >>> import tempfile
            >>> with tempfile.TemporaryDirectory() as tmp:
            ...     p = Portal(Path(tmp), Path(tmp) / "build" / "portal")
            ...     p.add_text("a.md", "x")
            ...     (p.write(), p.write())
            ((1, 0), (0, 0))

        See Also: Portal.add_text.
        """
        written = removed = 0
        for rel, content in self.files.items():
            target = self.out / rel
            if target.is_file() and target.read_bytes() == content:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            written += 1
        if self.out.is_dir():
            for path in sorted(self.out.rglob("*"), reverse=True):
                rel = path.relative_to(self.out).as_posix()
                if path.is_file() and rel not in self.files:
                    path.unlink()
                    removed += 1
                elif path.is_dir() and not any(path.iterdir()):
                    path.rmdir()
        return written, removed


def read_catalog(root: Path) -> list[Service]:
    """Read the service catalog.

    Summary:
        Parses ``templates/service/catalog.psv`` into :class:`Service` rows.

    Description:
        Blank lines and lines starting with ``#`` are skipped. Every other
        line must have exactly seven ``|``-separated columns.

    Business Justification:
        One machine-readable catalog feeds scaffolding, headers and the portal.

    Parameters:
        root (Path): repository root.

    Returns:
        list[Service]: services in catalog order (CLAUDE.md section 2).

    Errors:
        OSError: the catalog cannot be read.
        ValueError: a line does not have seven columns.

    Side Effects:
        Reads one file.

    Complexity: O(n) time and memory in the number of rows.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> root = Path(__file__).resolve().parent.parent
        >>> [s.name for s in read_catalog(root)][:2]
        ['gateway', 'auth']

    See Also: Service, scripts/new-service.sh.
    """
    services: list[Service] = []
    for line in root.joinpath(*CATALOG.parts).read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        columns = line.split("|")
        if len(columns) != 7:
            raise ValueError(f"{CATALOG}: expected 7 columns, got {len(columns)}: {line}")
        services.append(Service(len(services) + 1, *columns))
    return services


def read_topics(root: Path) -> list[list[str]]:
    """Read the topic registry.

    Summary:
        Parses ``contracts/events/topics.psv`` into rows of five columns.

    Description:
        Blank lines and lines starting with ``#`` are skipped. Every other
        line must have exactly five ``|``-separated columns: topic,
        partitions, producer, consumers and purpose. A missing registry
        yields an empty list, so the portal builds before the file exists.

    Business Justification:
        The registry that creates the topics on the broker also documents
        them, so the event catalog cannot drift from the running system.

    Parameters:
        root (Path): repository root.

    Returns:
        list[list[str]]: one ``[topic, partitions, producer, consumers,
        purpose]`` row per topic, in registry order.

    Errors:
        OSError: the registry exists but cannot be read.
        ValueError: a line does not have five columns.

    Side Effects:
        Reads one file.

    Complexity: O(n) time and memory in the number of rows.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.2.0

    Example:
        >>> root = Path(__file__).resolve().parent.parent
        >>> read_topics(root)[0][:2]
        ['aaas.key.pressed.v1', '3']
        >>> read_topics(Path("/nonexistent"))
        []

    See Also: generate_event_catalog, infra/redpanda/create-topics.sh.
    """
    path = root.joinpath(*TOPICS.parts)
    if not path.is_file():
        return []
    rows: list[list[str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        columns = line.split("|")
        if len(columns) != 5:
            raise ValueError(f"{TOPICS}: expected 5 columns, got {len(columns)}: {line}")
        rows.append(columns)
    return rows


def github_url(repo_path: str, is_dir: bool) -> str:
    """Build the GitHub URL of a repository path.

    Summary:
        Returns the ``blob`` (file) or ``tree`` (directory) URL on ``main``.

    Description:
        Used for links from portal documents to files that the portal does
        not contain (source code, CLAUDE.md, configuration).

    Business Justification:
        Readers of the portal can follow every link, not only links to pages.

    Parameters:
        repo_path (str): repository-relative POSIX path; empty for the root.
        is_dir (bool): ``True`` for a directory.

    Returns:
        str: absolute URL.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(n) time and memory in the length of the path.
    Thread Safety: safe (pure function).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> github_url("scripts/doc-check.sh", False)
        'https://github.com/JacKoz7/AaaS---Addition-as-a-Service/blob/main/scripts/doc-check.sh'

    See Also: rewrite_target.
    """
    kind = "tree" if is_dir else "blob"
    return f"{REPO_URL}/{kind}/{REPO_BRANCH}/{repo_path}".rstrip("/")


def portal_path(repo_path: str) -> str:
    """Map a repository path of a mirrored document to its portal path.

    Summary:
        Identity, except that the root ``README.md`` becomes ``index.md``.

    Description:
        MkDocs drops a ``README.md`` that sits next to an ``index.md``, and
        the portal home must be generated, so the root README is renamed.
        Other ``README.md`` files stay: MkDocs uses them as section indexes.

    Business Justification:
        The README is the natural landing page of the platform.

    Parameters:
        repo_path (str): repository-relative POSIX path.

    Returns:
        str: portal-relative POSIX path.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(1) time and memory.
    Thread Safety: safe (pure function).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> portal_path("README.md"), portal_path("services/carry/README.md")
        ('index.md', 'services/carry/README.md')

    See Also: rewrite_target.
    """
    return "index.md" if repo_path == "README.md" else repo_path


def rewrite_target(target: str, source: str, portal_files: set[str], root: Path) -> str:
    """Rewrite one link target of a mirrored document.

    Summary:
        Points a relative link at the portal page, or at GitHub.

    Description:
        Absolute URLs, anchors and absolute paths are returned unchanged.
        A relative target is resolved against the repository path of the
        document (``source``):

        - a file that is part of the portal: relative link to its portal path;
        - a directory with an ``index.md`` or ``README.md`` in the portal:
          relative link to that page (MkDocs validates links to pages, not
          to directories);
        - a file or directory that exists in the repository only: GitHub URL;
        - anything else (a broken link) is returned unchanged, so that the
          strict MkDocs build reports it.

        A ``#fragment`` is preserved.

    Business Justification:
        Documents link to repository paths so that they work on GitHub; the
        portal must keep those links working without editing the documents.

    Parameters:
        target (str): link target as written in the document.
        source (str): repository-relative path of the document.
        portal_files (set[str]): portal paths of every file in the portal.
        root (Path): repository root.

    Returns:
        str: the rewritten target.

    Errors:
        None.

    Side Effects:
        Reads file metadata (existence checks) in the repository.

    Complexity: O(d) time and memory, d being the depth of the path.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> root = Path(__file__).resolve().parent.parent
        >>> files = {"index.md", "docs/adr/index.md", "CONTRIBUTING.md"}
        >>> rewrite_target("../../README.md#why", "docs/onboarding/X.md", files, root)
        '../../index.md#why'
        >>> rewrite_target("docs/adr/", "CONTRIBUTING.md", files, root)
        'docs/adr/index.md'
        >>> rewrite_target("Makefile", "README.md", files, root)
        'https://github.com/JacKoz7/AaaS---Addition-as-a-Service/blob/main/Makefile'

    See Also: rewrite_links, portal_path, github_url.
    """
    angle = target.startswith("<") and target.endswith(">")
    bare = target[1:-1] if angle else target
    if not bare or bare.startswith(("#", "/")) or SCHEME.match(bare):
        return target
    path, hash_mark, fragment = bare.partition("#")
    suffix = hash_mark + fragment
    joined = os.path.normpath(os.path.join(os.path.dirname(source), path))
    if joined.startswith(".."):
        return target
    resolved = "" if joined == "." else joined.replace(os.sep, "/")
    here = os.path.dirname(portal_path(source)) or "."

    def relative(to: str) -> str:
        """Return the link from the document's portal directory to ``to``.

        Summary:
            Relative POSIX path from the source page to a portal path.

        Description:
            Closure over ``here`` (portal directory of the document).

        Business Justification:
            Portal links stay relative so the site works from any base URL.

        Parameters:
            to (str): portal-relative path of the target.

        Returns:
            str: relative path.

        Errors:
            None.

        Side Effects:
            None.

        Complexity: O(d) time and memory in the path depth.
        Thread Safety: safe (pure function).
        Owner: Platform Enablement Guild (PEG)
        Since: docs-portal 0.1.0

        Example:
            relative("index.md") from ``docs/adr`` is ``../../index.md``.

        See Also: rewrite_target.
        """
        return os.path.relpath(to, here).replace(os.sep, "/")

    if root.joinpath(resolved).is_dir() or path.endswith("/"):
        for page in ("index.md", "README.md"):
            candidate = portal_path(f"{resolved}/{page}".lstrip("/"))
            if candidate in portal_files:
                return relative(candidate) + suffix
        if root.joinpath(resolved).is_dir():
            return github_url(resolved, True) + suffix
        return target
    mapped = portal_path(resolved)
    if mapped in portal_files:
        return relative(mapped) + suffix
    if root.joinpath(resolved).exists():
        return github_url(resolved, False) + suffix
    return target


def rewrite_links(text: str, source: str, portal_files: set[str], root: Path) -> str:
    """Rewrite every link target of a Markdown document.

    Summary:
        Applies :func:`rewrite_target` to inline and reference links.

    Description:
        Fenced code blocks and inline code spans are left untouched, so code
        samples that look like links are not altered. HTML comments are not
        parsed specially; links inside them are rewritten too, which is
        harmless because comments are not rendered.

    Business Justification:
        See :func:`rewrite_target`.

    Parameters:
        text (str): Markdown source.
        source (str): repository-relative path of the document.
        portal_files (set[str]): portal paths of every file in the portal.
        root (Path): repository root.

    Returns:
        str: Markdown with rewritten link targets.

    Errors:
        None.

    Side Effects:
        Existence checks in the repository (via :func:`rewrite_target`).

    Complexity: O(n) time and memory in the length of ``text``.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> root = Path(__file__).resolve().parent.parent
        >>> rewrite_links("[a](README.md) `[b](README.md)`", "SECURITY.md", {"index.md"}, root)
        '[a](index.md) `[b](README.md)`'

    See Also: rewrite_target.
    """
    out: list[str] = []
    fence: str | None = None
    for line in text.splitlines(keepends=True):
        match = FENCE.match(line)
        if fence is not None:
            if match and match.group(1)[0] == fence[0] and len(match.group(1)) >= len(fence):
                fence = None
            out.append(line)
            continue
        if match:
            fence = match.group(1)
            out.append(line)
            continue
        reference = REFERENCE_LINK.match(line)
        if reference:
            new = rewrite_target(reference.group(2), source, portal_files, root)
            out.append(reference.group(1) + new + reference.group(3) + line[len(line.rstrip("\r\n")) :])
            continue
        pieces: list[str] = []
        last = 0
        for span in CODE_SPAN.finditer(line):
            pieces.append(_rewrite_inline(line[last : span.start()], source, portal_files, root))
            pieces.append(span.group(0))
            last = span.end()
        pieces.append(_rewrite_inline(line[last:], source, portal_files, root))
        out.append("".join(pieces))
    return "".join(out)


def _rewrite_inline(chunk: str, source: str, portal_files: set[str], root: Path) -> str:
    """Rewrite inline link targets in a fragment without code spans.

    Summary:
        Regex substitution of ``](target)`` occurrences.

    Description:
        Helper of :func:`rewrite_links`; the caller has removed code spans.

    Business Justification:
        See :func:`rewrite_target`.

    Parameters:
        chunk (str): part of a Markdown line outside code spans.
        source (str): repository-relative path of the document.
        portal_files (set[str]): portal paths of every file in the portal.
        root (Path): repository root.

    Returns:
        str: the fragment with rewritten targets.

    Errors:
        None.

    Side Effects:
        Existence checks in the repository.

    Complexity: O(n) time and memory in the length of ``chunk``.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> _rewrite_inline("see [x](#top)", "README.md", set(), Path("."))
        'see [x](#top)'

    See Also: rewrite_links.
    """
    return INLINE_LINK.sub(
        lambda m: m.group(1) + rewrite_target(m.group(2), source, portal_files, root) + m.group(3),
        chunk,
    )


def mirrored_documents(root: Path) -> list[str]:
    """List the repository files mirrored into the portal.

    Summary:
        Root documents, ``docs/`` (without ``docs/site``), component
        READMEs and ``docs/`` trees, and Markdown under ``contracts/``.

    Description:
        Markdown files and images (:data:`ASSET_SUFFIXES`) are mirrored;
        other files are linked on GitHub. The generated site ``docs/site``
        is excluded so the portal never contains itself.

    Business Justification:
        Every document of CLAUDE.md 6.5.5 and 6.5.6 appears in the portal.

    Parameters:
        root (Path): repository root.

    Returns:
        list[str]: sorted repository-relative POSIX paths.

    Errors:
        None (missing directories are skipped).

    Side Effects:
        Walks the file system.

    Complexity: O(f) time and memory in the number of files walked.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> root = Path(__file__).resolve().parent.parent
        >>> "docs/GLOSSARY.md" in mirrored_documents(root)
        True

    See Also: assemble.
    """
    found: set[str] = {name for name in ROOT_DOCUMENTS if (root / name).is_file()}
    trees = [root / "docs", root / "contracts"]
    for kind in ("services", "frontend"):
        for component in sorted((root / kind).glob("*/")):
            if (component / "README.md").is_file():
                found.add(f"{kind}/{component.name}/README.md")
            trees.append(component / "docs")
    for tree in trees:
        if not tree.is_dir():
            continue
        for path in tree.rglob("*"):
            rel = path.relative_to(root).as_posix()
            if rel.startswith("docs/site/") or not path.is_file():
                continue
            if path.suffix == ".md" or path.suffix.lower() in ASSET_SUFFIXES:
                found.add(rel)
    return sorted(found)


def table(header: list[str], rows: list[list[str]]) -> str:
    """Render a Markdown table.

    Summary:
        Joins a header and rows into pipe-table Markdown.

    Description:
        Pipes inside cells are escaped. An empty ``rows`` still renders the
        header so the reader sees the structure.

    Business Justification:
        Every catalog page is a table.

    Parameters:
        header (list[str]): column titles.
        rows (list[list[str]]): cells; each row has ``len(header)`` cells.

    Returns:
        str: Markdown table ending with a newline.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(cells) time and memory.
    Thread Safety: safe (pure function).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> print(table(["A"], [["x|y"]]), end="")
        | A |
        | --- |
        | x\\|y |

    See Also: generate_service_catalog.
    """
    lines = ["| " + " | ".join(header) + " |", "| " + " | ".join("---" for _ in header) + " |"]
    lines += ["| " + " | ".join(cell.replace("|", "\\|") for cell in row) + " |" for row in rows]
    return "\n".join(lines) + "\n"


def component_dir(root: Path, name: str) -> str | None:
    """Return the directory of a component present in the repository.

    Summary:
        ``services/<name>`` or ``frontend/<name>`` when it exists.

    Description:
        A component counts as present in the repository once its directory
        exists, which happens when it is scaffolded by
        ``scripts/new-service.sh``; whether its step is complete is recorded
        in ``docs/PROGRESS.md``, not here.

    Business Justification:
        The service map distinguishes services already in the repository
        from planned ones.

    Parameters:
        root (Path): repository root.
        name (str): component name.

    Returns:
        str | None: repository-relative directory, or ``None``.

    Errors:
        None.

    Side Effects:
        File-system existence checks.

    Complexity: O(1) time and memory.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> component_dir(Path("/nonexistent"), "carry") is None
        True

    See Also: generate_service_catalog.
    """
    for kind in ("services", "frontend"):
        if (root / kind / name).is_dir():
            return f"{kind}/{name}"
    return None


def generate_service_map(services: list[Service], root: Path) -> str:
    """Render the service map section of the home page.

    Summary:
        Mermaid flowchart of all services grouped by owning team.

    Description:
        One subgraph per team (CLAUDE.md 6.5.1), one node per service with
        its language. Services present in the repository are drawn solid;
        planned ones dashed. The map shows ownership, not traffic;
        the request flow is described in the C4 diagrams.

    Business Justification:
        CLAUDE.md 6.5.7 requires a service map on the portal home page.

    Parameters:
        services (list[Service]): the catalog.
        root (Path): repository root.

    Returns:
        str: Markdown section with a ``mermaid`` code block.

    Errors:
        None.

    Side Effects:
        File-system existence checks.

    Complexity: O(n) time and memory in the number of services.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> s = [Service(1, "gateway", "traefik", "Platform Enablement Guild",
        ...      "PEG", "Redis", "container", "Entry.")]
        >>> "gateway" in generate_service_map(s, Path("/nonexistent"))
        True

    See Also: generate_home.
    """
    lines = ["flowchart TB"]
    teams: dict[str, list[Service]] = {}
    for service in services:
        teams.setdefault(f"{service.team} ({service.abbr})", []).append(service)
    present: list[str] = []
    for index, (team, members) in enumerate(teams.items()):
        lines.append(f'  subgraph team{index}["{team}"]')
        lines.append("    direction LR")
        for service in members:
            node = service.name.replace("-", "_")
            lines.append(f'    {node}["{service.number}. {service.name}<br/><small>{service.language}</small>"]')
            if component_dir(root, service.name):
                present.append(node)
        lines.append("  end")
    lines.append("  classDef planned stroke-dasharray: 4 4,opacity:0.7")
    planned = [s.name.replace("-", "_") for s in services if s.name.replace("-", "_") not in present]
    if planned:
        lines.append(f"  class {','.join(planned)} planned")
    count = len(present)
    return (
        "\n## Service map\n\n"
        "Services grouped by owning team. Solid boxes are services present in "
        f"the repository ({count} of {len(services)}); dashed boxes are planned. "
        "Step status is tracked in [progress](docs/PROGRESS.md). The "
        "[service catalog](catalog/services.md) links every service to its "
        "documents.\n\n```mermaid\n" + "\n".join(lines) + "\n```\n"
    )


def generate_home(readme: str, services: list[Service], root: Path) -> str:
    """Compose the portal home page.

    Summary:
        README content followed by the service map and the portal contents.

    Description:
        The README keeps its links (it sits at the same level as
        ``index.md``); the generated sections are appended.

    Business Justification:
        A single landing page for every stakeholder of AaaS.

    Parameters:
        readme (str): rewritten README Markdown.
        services (list[Service]): the catalog.
        root (Path): repository root.

    Returns:
        str: Markdown of ``index.md``.

    Errors:
        None.

    Side Effects:
        File-system existence checks.

    Complexity: O(n) time and memory in the README and catalog size.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> generate_home("# AaaS\\n", [], Path("/nonexistent")).startswith("# AaaS")
        True

    See Also: generate_service_map.
    """
    contents = (
        "\n## Portal contents\n\n"
        "- [Service catalog](catalog/services.md), [event catalog](catalog/events.md), "
        "[API catalog](catalog/api.md) and [changelogs](catalog/changelogs.md)\n"
        "- [C4 system context](docs/architecture/c4/context.md)\n"
        "- [Architecture decision records](docs/adr/index.md) and [RFCs](docs/rfc/index.md)\n"
        "- [Risk register](docs/governance/RISK_REGISTER.md) and the rest of the governance documents\n"
        "- [Progress](docs/PROGRESS.md) and the [step logs](docs/progress/steps/index.md)\n"
    )
    return readme.rstrip("\n") + "\n" + generate_service_map(services, root) + contents


def generate_service_catalog(services: list[Service], root: Path, portal_files: set[str]) -> str:
    """Render the service catalog page.

    Summary:
        Table of the 35 services with team, technology, database, status and
        links to every document that exists.

    Description:
        Links point to the component README, each corporate document of
        CLAUDE.md 6.5.5 that exists, and the native API documentation when
        ``make docs`` produced it. Microfrontend directories that exist are
        listed in a second table.

    Business Justification:
        CLAUDE.md 6.5.7: catalog of services with links to their documents.

    Parameters:
        services (list[Service]): the catalog.
        root (Path): repository root.
        portal_files (set[str]): portal paths of every file in the portal.

    Returns:
        str: Markdown of ``catalog/services.md``.

    Errors:
        None.

    Side Effects:
        File-system existence checks.

    Complexity: O(n) time and memory in the number of services.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> generate_service_catalog([], Path("/nonexistent"), set()).splitlines()[0]
        '# Service Catalog'

    See Also: component_links.
    """
    rows = []
    for s in services:
        directory = component_dir(root, s.name)
        status = "In repository" if directory else "Planned"
        links = component_links(directory, portal_files) if directory else "—"
        rows.append([str(s.number), f"`{s.name}`", s.abbr, s.language, s.database, status, s.purpose, links])
    frontends = sorted(p.name for p in (root / "frontend").glob("*/")) if (root / "frontend").is_dir() else []
    frontend_rows = [[f"`{name}`", component_links(f"frontend/{name}", portal_files)] for name in frontends]
    page = (
        "# Service Catalog\n\n"
        "Every service of AaaS (CLAUDE.md, section 2), generated from "
        "`templates/service/catalog.psv`. A service is *In repository* once its "
        "directory exists in `services/`; the completion of its step is tracked in "
        "[progress](../docs/PROGRESS.md). Team abbreviations are explained in "
        "the [glossary](../docs/GLOSSARY.md).\n\n"
        + table(["#", "Service", "Team", "Technology", "Database", "Status", "Role", "Documents"], rows)
        + "\n## Microfrontends\n\n"
    )
    if frontend_rows:
        return page + table(["Element", "Documents"], frontend_rows)
    return page + "No microfrontend directory exists in `frontend/` yet.\n"


def component_links(directory: str, portal_files: set[str]) -> str:
    """Render the document links of one component.

    Summary:
        Comma-separated links to README, corporate documents and API docs.

    Description:
        Only documents present in the portal are linked; links are relative
        to ``catalog/``.

    Business Justification:
        One click from the catalog to any document of a service.

    Parameters:
        directory (str): ``services/<name>`` or ``frontend/<name>``.
        portal_files (set[str]): portal paths of every file in the portal.

    Returns:
        str: Markdown links, or ``—`` when there is none.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(k) time and memory, k = number of document kinds.
    Thread Safety: safe (pure function).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> component_links("services/carry", {"services/carry/README.md"})
        '[README](../services/carry/README.md)'

    See Also: generate_service_catalog.
    """
    links = []
    if f"{directory}/README.md" in portal_files:
        links.append(f"[README](../{directory}/README.md)")
    for document in COMPONENT_DOCUMENTS:
        if f"{directory}/docs/{document}" in portal_files:
            label = document.removesuffix(".md").replace("_", " ").title().replace("Slo", "SLO")
            label = label.replace("Raci", "RACI").replace("Api", "API")
            links.append(f"[{label}](../{directory}/docs/{document})")
    name = directory.split("/", 1)[1]
    if f"api/{name}/index.html" in portal_files:
        links.append(f"[Native API docs](../api/{name}/index.html)")
    return ", ".join(links) or "—"


def generate_event_catalog(root: Path) -> str:
    """Render the event catalog page.

    Summary:
        Tables of every topic in the registry and every JSON Schema in
        ``contracts/events/``.

    Description:
        The topic table comes from ``contracts/events/topics.psv``: topic,
        partitions, producer, consumers, purpose, and the schema file whose
        ``title`` equals the topic, if any. The schema table lists, for each
        ``*.json`` file, the schema ``title`` (the topic), its
        ``description`` and ``$id``, and a link to the source file on GitHub.
        A file that is not valid JSON is reported with a warning, which fails
        the strict build.

    Business Justification:
        CLAUDE.md 6.5.7: event catalog generated from JSON Schema; the topic
        registry adds who produces and consumes each event.

    Parameters:
        root (Path): repository root.

    Returns:
        str: Markdown of ``catalog/events.md``.

    Errors:
        ValueError: a topic registry line does not have five columns
        (invalid schemas are logged, not raised).

    Side Effects:
        Reads the topic registry and schema files; logs a warning per
        invalid schema file.

    Complexity: O(total registry and schema size) time and memory.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> page = generate_event_catalog(Path("/nonexistent"))
        >>> "No topic is registered" in page and "No event schema" in page
        True

    See Also: read_topics, CLAUDE.md 4.2, contracts/events/.
    """
    page = (
        "# Event Catalog\n\n"
        "Events published on Redpanda (CLAUDE.md, section 4.2), generated from "
        "the topic registry `contracts/events/topics.psv` and the JSON Schemas "
        "in `contracts/events/`. Messages are keyed by `taskId`; every topic has "
        "replication factor 1, `cleanup.policy=delete` and seven days of "
        "retention (ADR-0011).\n\n"
    )
    schemas = (
        sorted((root / "contracts" / "events").rglob("*.json")) if (root / "contracts" / "events").is_dir() else []
    )
    schema_rows = []
    schema_by_topic: dict[str, str] = {}
    for path in schemas:
        rel = path.relative_to(root).as_posix()
        try:
            schema = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            LOG.warning("%s: not a readable JSON Schema: %s", rel, error)
            continue
        if not isinstance(schema, dict):
            LOG.warning("%s: a JSON Schema must be an object", rel)
            continue
        link = f"[{path.name}]({github_url(rel, False)})"
        schema_by_topic[str(schema.get("title", path.stem))] = link
        schema_rows.append(
            [
                f"`{schema.get('title', path.stem)}`",
                str(schema.get("description", "—")).replace("\n", " "),
                f"`{schema.get('$id', '—')}`",
                link,
            ]
        )
    topic_rows = [
        [f"`{topic}`", partitions, producer, consumers, purpose, schema_by_topic.get(topic, "—")]
        for topic, partitions, producer, consumers, purpose in read_topics(root)
    ]
    page += "## Topics\n\n"
    if topic_rows:
        page += table(["Topic", "Partitions", "Producer", "Consumers", "Purpose", "Schema"], topic_rows)
    else:
        page += "No topic is registered in `contracts/events/topics.psv` yet.\n"
    page += "\n## Schemas\n\n"
    if not schema_rows:
        return page + "No event schema exists in `contracts/events/` yet.\n"
    return page + table(["Event", "Description", "Schema ID", "Source"], schema_rows)


def generate_api_catalog(root: Path, portal_files: set[str]) -> str:
    """Render the API catalog page.

    Summary:
        Lists OpenAPI documents, proto packages and native API documentation.

    Description:
        OpenAPI documents are ``contracts/http/*.yaml`` (and ``*.yml``);
        proto files are ``contracts/proto/**/*.proto``, grouped by directory
        (one gRPC package per directory); native API documentation is every
        ``api/<component>/index.html`` in the portal.

    Business Justification:
        CLAUDE.md 6.5.7: API catalog of OpenAPI and proto contracts.

    Parameters:
        root (Path): repository root.
        portal_files (set[str]): portal paths of every file in the portal.

    Returns:
        str: Markdown of ``catalog/api.md``.

    Errors:
        None.

    Side Effects:
        Walks ``contracts/``.

    Complexity: O(f) time and memory in the number of contract files.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> generate_api_catalog(Path("/nonexistent"), set()).splitlines()[0]
        '# API Catalog'

    See Also: CLAUDE.md 4.1, 4.3, 4.4.
    """
    contracts = root / "contracts"
    openapi = sorted(contracts.glob("http/*.y*ml")) if contracts.is_dir() else []
    protos = sorted(contracts.glob("proto/**/*.proto")) if contracts.is_dir() else []
    native = sorted(p.split("/")[1] for p in portal_files if re.fullmatch(r"api/[^/]+/index\.html", p))
    page = ["# API Catalog\n", "Public API (CLAUDE.md 4.1), gRPC (4.3) and HTTP/JSON (4.4) contracts.\n"]
    page.append("## OpenAPI documents\n")
    if openapi:
        rows = [[f"`{p.name}`", f"[source]({github_url(p.relative_to(root).as_posix(), False)})"] for p in openapi]
        page.append(table(["Document", "Source"], rows))
    else:
        page.append("No OpenAPI document exists in `contracts/http/` yet.\n")
    page.append("## gRPC packages\n")
    if protos:
        packages: dict[str, list[Path]] = {}
        for proto in protos:
            packages.setdefault(proto.parent.relative_to(contracts / "proto").as_posix(), []).append(proto)
        rows = [
            [
                f"`{package.replace('/', '.')}`",
                ", ".join(f"[{p.name}]({github_url(p.relative_to(root).as_posix(), False)})" for p in files),
            ]
            for package, files in sorted(packages.items())
        ]
        page.append(table(["Package", "Files"], rows))
    else:
        page.append("No proto file exists in `contracts/proto/` yet.\n")
    page.append("## Native API documentation\n")
    if native:
        page.append(
            table(["Component", "Documentation"], [[f"`{n}`", f"[open](../api/{n}/index.html)"] for n in native])
        )
    else:
        page.append("No component has produced native API documentation yet (`make docs`, ADR-0010).\n")
    return "\n".join(page)


def generate_changelog_catalog(root: Path, portal_files: set[str]) -> str:
    """Render the changelog index page.

    Summary:
        Links to the ``CHANGELOG.md`` of every component.

    Description:
        Components are found by the presence of ``docs/CHANGELOG.md`` in
        ``services/*`` and ``frontend/*``.

    Business Justification:
        CLAUDE.md 6.5.7 and 6.5.8: changelogs of every service in one place.

    Parameters:
        root (Path): repository root (unused; kept for a uniform signature).
        portal_files (set[str]): portal paths of every file in the portal.

    Returns:
        str: Markdown of ``catalog/changelogs.md``.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(f log f) time, O(f) memory in the number of portal files.
    Thread Safety: safe (pure function).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> "[`carry`]" in generate_changelog_catalog(Path("."), {"services/carry/docs/CHANGELOG.md"})
        True

    See Also: cliff.toml, scripts/changelog.sh.
    """
    del root
    changelogs = sorted(p for p in portal_files if re.fullmatch(r"(services|frontend)/[^/]+/docs/CHANGELOG\.md", p))
    page = (
        "# Changelogs\n\n"
        "Per-component changelogs (Keep a Changelog, SemVer, tags `<component>/vX.Y.Z`), "
        "generated by git-cliff with `make changelog-<component>` and completed by hand "
        "with a Business Impact section ([release process](../docs/governance/RELEASE_PROCESS.md)).\n\n"
    )
    if not changelogs:
        return page + "No component has a changelog yet.\n"
    return page + "".join(f"- [`{p.split('/')[1]}`](../{p})\n" for p in changelogs)


def metadata(text: str, field: str) -> str:
    """Read a field from the metadata table of a document.

    Summary:
        Returns the value of the row ``| <field> | <value> |``.

    Description:
        ADRs, RFCs and step logs start with a two-column metadata table.

    Business Justification:
        Indexes show status and date without duplicating them.

    Parameters:
        text (str): Markdown document.
        field (str): field name, e.g. ``Status``.

    Returns:
        str: the value, or ``—`` when the row is missing or empty.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(n) time, O(1) extra memory.
    Thread Safety: safe (pure function).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> metadata("| Status | Accepted |\\n", "Status")
        'Accepted'

    See Also: generate_record_index.
    """
    match = re.search(rf"^\|\s*{re.escape(field)}\s*\|\s*(.*?)\s*\|\s*$", text, re.MULTILINE)
    return match.group(1) if match and match.group(1) else "—"


def title(text: str, fallback: str) -> str:
    """Return the first level-one heading of a document.

    Summary:
        Text of the first ``# `` line.

    Description:
        Falls back to ``fallback`` when the document has no H1.

    Business Justification:
        Index entries carry the document's own title.

    Parameters:
        text (str): Markdown document.
        fallback (str): value used without an H1.

    Returns:
        str: the title.

    Errors:
        None.

    Side Effects:
        None.

    Complexity: O(n) time, O(1) extra memory.
    Thread Safety: safe (pure function).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> title("x\\n# ADR-0001: Records\\n", "f")
        'ADR-0001: Records'

    See Also: metadata.
    """
    match = re.search(r"^# (.+)$", text, re.MULTILINE)
    return match.group(1).strip() if match else fallback


def generate_record_index(root: Path, directory: str, heading: str, intro: str, pattern: str, fields: list[str]) -> str:
    """Render an index of numbered records (ADRs, RFCs, step logs, releases).

    Summary:
        Table of the documents in ``directory`` whose names match ``pattern``.

    Description:
        Each row links the document (relative to the index in the same
        directory) with its H1 title and the requested metadata fields.
        Used for ADRs, RFCs, step logs and phase release notes.

    Business Justification:
        CLAUDE.md 6.5.7 requires the ADRs and RFCs in the portal; the step
        logs are the audit trail of the delivery.

    Parameters:
        root (Path): repository root.
        directory (str): repository-relative directory, e.g. ``docs/adr``.
        heading (str): page title.
        intro (str): paragraph under the title.
        pattern (str): regular expression matched against file names.
        fields (list[str]): metadata fields shown as columns.

    Returns:
        str: Markdown of ``<directory>/index.md``.

    Errors:
        OSError: a matching document cannot be read.

    Side Effects:
        Reads the matching documents.

    Complexity: O(total size of the documents) time and memory.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> root = Path(__file__).resolve().parent.parent
        >>> "0001-record" in generate_record_index(root, "docs/adr", "ADRs", "", r"\\d{4}-.+\\.md", ["Status"])
        True

    See Also: metadata, title.
    """
    folder = root / directory
    paths = sorted(p for p in folder.glob("*.md") if re.fullmatch(pattern, p.name)) if folder.is_dir() else []
    rows = []
    for path in paths:
        text = path.read_text(encoding="utf-8")
        rows.append([f"[{title(text, path.stem)}]({path.name})"] + [metadata(text, f) for f in fields])
    body = table(["Document"] + fields, rows) if rows else "No document yet.\n"
    return f"# {heading}\n\n{intro}\n\n{body}"


def collect_api_docs(root: Path, portal: Portal) -> None:
    """Add the native API documentation of every component.

    Summary:
        Copies ``build/api-docs/<component>/**`` to ``api/<component>/``.

    Description:
        ``make docs`` exports each component's native documentation (rustdoc,
        Haddock, ExDoc, ...) to ``build/api-docs/<component>/`` first.
        Components without an ``index.html`` there are skipped.

    Business Justification:
        CLAUDE.md 6.5.7: the portal includes the generated API documentation
        of every service.

    Parameters:
        root (Path): repository root.
        portal (Portal): portal being assembled.

    Returns:
        None.

    Errors:
        OSError: a file cannot be read.

    Side Effects:
        Reads files under ``build/api-docs``.

    Complexity: O(total size of the API docs) time and memory.
    Thread Safety: not thread-safe (mutates ``portal``).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> p = Portal(Path("/nonexistent"), Path("/nonexistent/build/portal"))
        >>> collect_api_docs(Path("/nonexistent"), p); p.files
        {}

    See Also: Makefile target ``docs``, templates/service/Dockerfile.tmpl.
    """
    base = root.joinpath(*API_DOCS_DIR.parts)
    if not base.is_dir():
        return
    for component in sorted(base.iterdir()):
        if not (component / "index.html").is_file():
            continue
        for path in component.rglob("*"):
            if path.is_file():
                portal.add_copy(f"api/{component.name}/{path.relative_to(component).as_posix()}", path)


def assemble(root: Path, out: Path) -> tuple[int, int]:
    """Assemble the whole portal.

    Summary:
        Mirrors, rewrites and generates every portal file, then writes them.

    Description:
        Order matters: the set of portal paths must be complete before links
        are rewritten, because a link points into the portal only when its
        target is part of it. Generated pages are registered first, then
        mirrored documents; a mirrored document never has the path of a
        generated page except where a generated index replaces a missing one.

    Business Justification:
        Single entry point used by the MkDocs hook and by the command line.

    Parameters:
        root (Path): repository root.
        out (Path): portal directory (``<root>/build/portal``).

    Returns:
        tuple[int, int]: files written and files removed.

    Errors:
        ValueError: ``out`` is not the portal directory, or the catalog is
            malformed.
        OSError: a file cannot be read or written.

    Side Effects:
        Reads the repository and rewrites ``build/portal``.

    Complexity: O(total size of the documentation) time and memory.
    Thread Safety: not thread-safe; one assembly at a time per directory.
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        assemble(Path("."), Path("build/portal"))  # returns e.g. (42, 0)

    See Also: on_pre_build, main.
    """
    portal = Portal(root, out)
    services = read_catalog(root)
    documents = mirrored_documents(root)
    collect_api_docs(root, portal)
    for name in ROOT_PLAIN_FILES:
        if (root / name).is_file():
            portal.add_copy(name, root / name)
    generated = {
        "docs/adr/index.md": None,
        "docs/rfc/index.md": None,
        "docs/progress/steps/index.md": None,
        "docs/releases/index.md": None,
        "catalog/services.md": None,
        "catalog/events.md": None,
        "catalog/api.md": None,
        "catalog/changelogs.md": None,
    }
    portal_files = set(portal.files) | set(generated) | {portal_path(d) for d in documents}
    for document in documents:
        source = root / document
        if source.suffix != ".md":
            portal.add_copy(document, source)
            continue
        text = rewrite_links(source.read_text(encoding="utf-8"), document, portal_files, root)
        if document == "README.md":
            text = generate_home(text, services, root)
        portal.add_text(portal_path(document), text)
    portal.add_text(
        "docs/adr/index.md",
        generate_record_index(
            root,
            "docs/adr",
            "Architecture Decision Records",
            "Every architectural decision not contained in `CLAUDE.md` "
            "([ADR-0001](0001-record-architecture-decisions.md)).",
            r"\d{4}-.+\.md",
            ["Status", "Date", "Step"],
        ),
    )
    portal.add_text(
        "docs/rfc/index.md",
        generate_record_index(
            root,
            "docs/rfc",
            "Requests for Comments",
            "Changes spanning more than one service "
            "([RFC process](../governance/RFC_PROCESS.md), [template](TEMPLATE.md)).",
            r"\d{4}-.+\.md",
            ["Status"],
        ),
    )
    portal.add_text(
        "docs/progress/steps/index.md",
        generate_record_index(
            root,
            "docs/progress/steps",
            "Step Logs",
            "Snapshot log of every step ([progress](../../PROGRESS.md), [template](TEMPLATE.md)).",
            r"P\d+\.\d+[a-z]?\.md",
            ["Status", "Completed", "Snapshot tag"],
        ),
    )
    portal.add_text(
        "docs/releases/index.md",
        generate_record_index(
            root,
            "docs/releases",
            "Release Notes",
            "Announcement of every completed phase ([release process](../governance/RELEASE_PROCESS.md)).",
            r"phase-\d+\.md",
            ["Date", "Milestone", "Tag"],
        ),
    )
    portal.add_text("catalog/services.md", generate_service_catalog(services, root, portal_files))
    portal.add_text("catalog/events.md", generate_event_catalog(root))
    portal.add_text("catalog/api.md", generate_api_catalog(root, portal_files))
    portal.add_text("catalog/changelogs.md", generate_changelog_catalog(root, portal_files))
    return portal.write()


def on_pre_build(config: dict) -> None:
    """MkDocs hook: assemble the portal before the files are collected.

    Summary:
        Runs :func:`assemble` with the ``docs_dir`` of the configuration.

    Description:
        MkDocs calls this before every build, including every rebuild of
        ``mkdocs serve``. The repository root is the directory of
        ``mkdocs.yml``.

    Business Justification:
        One command (``make docs``) produces a complete, current portal.

    Parameters:
        config (dict): MkDocs configuration (``MkDocsConfig``); the keys
            ``config_file_path`` and ``docs_dir`` are used.

    Returns:
        None.

    Errors:
        ValueError, OSError: see :func:`assemble`; MkDocs aborts the build.

    Side Effects:
        Rewrites ``build/portal``; logs one INFO line.

    Complexity: see :func:`assemble`.
    Thread Safety: not thread-safe; MkDocs builds sequentially.
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        Configured in mkdocs.yml as ``hooks: [scripts/docs-portal.py]``.

    See Also: assemble, mkdocs.yml.
    """
    root = Path(config["config_file_path"]).resolve().parent
    written, removed = assemble(root, Path(config["docs_dir"]))
    LOG.info("portal assembled: %d file(s) written, %d removed", written, removed)


def main(argv: list[str]) -> int:
    """Command-line entry point: assemble the portal without building it.

    Summary:
        ``python3 scripts/docs-portal.py`` writes ``build/portal``.

    Description:
        Useful to inspect the generated Markdown. No arguments are accepted.

    Business Justification:
        Troubleshooting the portal without running MkDocs.

    Parameters:
        argv (list[str]): command-line arguments without the program name.

    Returns:
        int: exit status, 0 on success, 2 on usage errors.

    Errors:
        ValueError, OSError: see :func:`assemble`.

    Side Effects:
        Rewrites ``build/portal``; prints one line.

    Complexity: see :func:`assemble`.
    Thread Safety: not applicable (process entry point).
    Owner: Platform Enablement Guild (PEG)
    Since: docs-portal 0.1.0

    Example:
        >>> main(["--help"])
        usage: scripts/docs-portal.py  (assembles build/portal; no options)
        2

    See Also: on_pre_build.
    """
    if argv:
        print("usage: scripts/docs-portal.py  (assembles build/portal; no options)")
        return 2
    root = Path(__file__).resolve().parent.parent
    written, removed = assemble(root, root.joinpath(*PORTAL_DIR.parts))
    print(f"portal assembled in {PORTAL_DIR}: {written} file(s) written, {removed} removed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
