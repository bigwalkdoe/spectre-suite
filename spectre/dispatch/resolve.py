"""Turn a registry entry into a verified absolute path plus git provenance.

Resolution is the dispatcher's containment guard, and the incident it exists for
is a wrapper script that was a symlink to a copy of itself left elsewhere on the
host: the scheduler's path check was satisfied by the symlink while the code that
actually ran was not the reviewed code. So the target is fully resolved — symlinks
followed — *before* anything else is checked, and a target that leaves the actions
root is refused with the real path named rather than executed.

The three checks run containment, then existence, then executability, because the
order decides the message: a path that escapes the checkout is a different and
more serious problem than a missing file. None of them is allowed to pass quietly
— a job whose action is absent must fail loudly, since a dispatcher that skips it
is how a maintenance suite silently stops running.

Provenance answers "which revision of this checkout ran this, and was it dirty?",
read from the repository *containing* the actions root — which is normally the
repository itself, since the default root is a subdirectory of the checkout. A
root outside any repository yields empty provenance instead of raising, because
the actions root is legitimately a plain directory in tests and elsewhere.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

try:
    import git  # type: ignore[import-not-found]
except Exception:  # pragma: no cover - optional dep (GitPython)
    git = None  # type: ignore[assignment]

from spectre.dispatch.registry import Job

# How much of the HEAD sha is recorded: the same seven hex digits `git log`
# abbreviates to, so a recorded commit can be pasted into a log and resolved.
_SHORT_SHA_LENGTH = 7

# `spectre run`'s exit code for "registered, but not dispatchable" — absent, not
# executable, or resolving outside the checkout. Distinct from 2 (unknown job) and
# 5 (the action ran and failed), so a caller can tell a refusal from a failure.
_NOT_DISPATCHABLE = 3


class DispatchError(Exception):
    """A job cannot be dispatched, and the process should exit `exit_code`."""

    def __init__(self, message: str, exit_code: int = _NOT_DISPATCHABLE) -> None:
        super().__init__(message)
        self.exit_code = exit_code


@dataclass(frozen=True)
class ResolvedAction:
    """A job's action as an absolute path inside the checkout, plus provenance."""

    job: Job
    path: Path
    git_commit: str
    git_dirty: bool


def repo_root() -> Path:
    """The checkout this package was imported from.

    `parents[0]` is `spectre/dispatch`, `[1]` is `spectre`, `[2]` is the
    repository root. Resolved, because the location an installed wheel is
    unpacked into is not a useful place to look for the actions.
    """
    return Path(__file__).resolve().parents[2]


def actions_root() -> Path:
    """Where actions live: `$SPECTRE_ACTIONS_ROOT`, else the unified/suite layout.

    Unified layout (Phase 1): `<repo>/spectre/actions`. Compatibility: `<repo>/scripts`.
    Legacy: `<repo>/actions`. Absolute and fully resolved in all branches.
    """
    configured = os.environ.get("SPECTRE_ACTIONS_ROOT")
    if configured:
        return Path(configured).resolve()
    root = repo_root()
    for candidate in (root / "spectre" / "actions", root / "scripts", root / "actions"):
        if candidate.is_dir():
            return candidate.resolve()
    return (root / "spectre" / "actions").resolve()


def _provenance(root: Path) -> tuple[str, bool]:
    """(short HEAD sha, dirty) for the repository holding `root`; ("", False)
    when there is none or GitPython is unavailable.
    """
    if git is None:
        return "", False
    try:
        repo = git.Repo(root, search_parent_directories=True)
        return repo.head.commit.hexsha[:_SHORT_SHA_LENGTH], repo.is_dirty()
    except Exception:
        # InvalidGitRepositoryError, ValueError (no commits), or other git issues
        return "", False


def resolve(job: Job) -> ResolvedAction:
    """The job's action as a verified absolute path, with the checkout's provenance.

    Raises `DispatchError` naming the path and the reason. Nothing here executes
    anything, and no failure is softened into a skip.

    **Every malformed `action` raises `DispatchError`, not a bare exception.** A NUL
    in the path makes `Path.resolve` raise `ValueError` from the C layer, which
    reached the caller as a traceback instead of the documented exit 3 — the one
    code that means "registered but not dispatchable". A registry value is data, and
    data that cannot be turned into a path has no more business raising
    `ValueError` than a missing file does.
    """
    root = actions_root()
    try:
        target = (root / job.action).resolve()
    except (OSError, ValueError) as e:
        # `ValueError` here is the embedded-NUL case; `OSError` is a path too long
        # or a looped symlink. Both are the same fact to a caller: this action's path
        # is not a path.
        raise DispatchError(f"job {job.name} has an unusable action path {job.action!r}: {e}") from None

    # An absolute `action` replaces the root rather than extending it, so this
    # also refuses `/etc/whatever` and not just `../` traversal.
    if not target.is_relative_to(root):
        raise DispatchError(f"job {job.name} resolves outside the actions root: {target}")
    if not target.exists():
        raise DispatchError(f"job {job.name} action is missing: {target}")
    # A *directory* is present and passes `os.access(X_OK)` — every directory on the
    # host is executable, since that is what the bit means. A directory named
    # `cleanup.sh` therefore satisfied both checks above and reached `Popen`, which
    # failed with exit 126 and was recorded as a failed run: the dispatcher said the
    # action ran, and the run record said it succeeded at nothing. `is_file` is the
    # check that matches what is going to be executed.
    if not target.is_file():
        raise DispatchError(f"job {job.name} action is not a file: {target}")
    if not os.access(target, os.X_OK):
        raise DispatchError(f"job {job.name} action is not executable: {target}")

    git_commit, git_dirty = _provenance(root)
    return ResolvedAction(job=job, path=target, git_commit=git_commit, git_dirty=git_dirty)
