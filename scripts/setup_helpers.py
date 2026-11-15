#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import re
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path
from typing import Iterable


def run(command: Iterable[str], *, cwd: Path | None = None, timeout: float | None = None) -> None:
    printable = " ".join(str(item) for item in command)
    print(f"+ {printable}")
    subprocess.run(
        [str(item) for item in command],
        cwd=cwd,
        check=True,
        timeout=timeout,
    )


def git_output(repo: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo), *args], text=True, stderr=subprocess.STDOUT
    ).strip()


def fetch_git_repo(
    destination: Path,
    revision: str,
    url: str = "origin",
    *,
    timeout: float = 300,
    attempts: int = 3,
    no_tags: bool = False,
    no_write_fetch_head: bool = False,
) -> None:
    """Fetch a locked revision with a per-attempt timeout and bounded retries."""
    if attempts < 1 or timeout <= 0:
        raise ValueError("fetch attempts and timeout must be positive")
    destination = destination.resolve()
    command = ["git", "fetch"]
    if no_tags:
        command.append("--no-tags")
    if no_write_fetch_head:
        command.append("--no-write-fetch-head")
    command.extend(("--depth", "1", url, revision))
    for attempt in range(attempts):
        try:
            run(command, cwd=destination, timeout=timeout)
            return
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            if attempt + 1 == attempts:
                raise
            delay = 2**attempt
            print(f"[dependency] fetch retry {attempt + 2}/{attempts}: {destination.name} in {delay}s")
            time.sleep(delay)


def ensure_git_commit(
    url: str,
    destination: Path,
    revision: str,
    *,
    fetch_timeout: float = 300,
    fetch_attempts: int = 3,
) -> None:
    """Fetch a locked historical object without switching the active checkout."""
    if re.fullmatch(r"[0-9a-f]{40}", revision) is None:
        raise ValueError("historical dependency requires a full Git commit revision")
    destination = destination.resolve()
    if not (destination / ".git").exists():
        raise RuntimeError(f"prepare the current dependency checkout first: {destination}")
    try:
        git_output(destination, "cat-file", "-e", f"{revision}^{{commit}}")
    except subprocess.CalledProcessError:
        # No checkout/refspec: preserve HEAD, index, worktree and FETCH_HEAD.
        fetch_git_repo(
            destination,
            revision,
            url,
            timeout=fetch_timeout,
            attempts=fetch_attempts,
            no_tags=True,
            no_write_fetch_head=True,
        )
    if git_output(destination, "rev-parse", f"{revision}^{{commit}}") != revision:
        raise RuntimeError(f"historical dependency commit mismatch: {destination}: {revision}")
    print(f"[dependency] historical object available: {destination.name}: {revision}")


def canonical_git_url(value: str) -> str:
    normalized = value.rstrip("/")
    if normalized.startswith("git@github.com:"):
        normalized = "https://github.com/" + normalized.removeprefix("git@github.com:")
    if normalized.startswith("https://github.com/") and normalized.endswith(".git"):
        normalized = normalized.removesuffix(".git")
    return normalized


def validate_locked_reference(reference: Path, url: str, revision: str) -> Path:
    if reference.is_symlink():
        raise RuntimeError(f"dependency reference must not be a symlink: {reference}")
    reference = reference.resolve()
    if not (reference / ".git").exists():
        raise RuntimeError(f"dependency reference is not a Git worktree: {reference}")
    if git_output(reference, "rev-parse", "--show-toplevel") != str(reference):
        raise RuntimeError(f"dependency reference must be a top-level worktree: {reference}")
    if re.fullmatch(r"[0-9a-f]{40}", revision) is None:
        raise ValueError("locked dependency requires a full Git commit revision")
    if git_output(reference, "rev-parse", "HEAD") != revision:
        raise RuntimeError(f"dependency reference revision mismatch: {reference}")
    if git_output(reference, "rev-parse", f"{revision}^{{commit}}") != revision:
        raise RuntimeError(f"dependency reference object mismatch: {reference}")
    if canonical_git_url(git_output(reference, "remote", "get-url", "origin")) != canonical_git_url(url):
        raise RuntimeError(f"dependency reference remote mismatch: {reference}")
    if git_output(reference, "status", "--porcelain", "--untracked-files=all"):
        raise RuntimeError(f"dependency reference has local changes: {reference}")
    return reference


def ensure_git_repo(
    url: str,
    destination: Path,
    revision: str,
    *,
    recursive: bool = False,
    submodules: tuple[str, ...] = (),
    update: bool = False,
    allow_dirty: bool = False,
    fetch_timeout: float = 300,
    fetch_attempts: int = 3,
    reference: Path | None = None,
) -> None:
    """Fetch a locked revision, or copy a validated reference without shared state."""
    destination = destination.resolve()
    if reference is not None:
        if recursive or submodules:
            raise ValueError("reference restore does not bypass recursive submodule setup")
        reference = validate_locked_reference(reference, url, revision)
    fetch_url = str(reference) if reference is not None else url
    created = False
    if not destination.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        run(("git", "init", str(destination)))
        run(("git", "remote", "add", "origin", url), cwd=destination)
        fetch_git_repo(destination, revision, fetch_url, timeout=fetch_timeout, attempts=fetch_attempts)
        run(("git", "checkout", "--detach", "FETCH_HEAD"), cwd=destination)
        created = True
    elif not (destination / ".git").exists():
        raise RuntimeError(f"dependency path is not a Git repository: {destination}")

    try:
        current = git_output(destination, "rev-parse", "HEAD")
    except subprocess.CalledProcessError:
        if git_output(destination, "status", "--porcelain"):
            raise RuntimeError(f"unborn dependency has local changes: {destination}")
        if git_output(destination, "remote", "get-url", "origin") != url:
            raise RuntimeError(f"unborn dependency remote mismatch: {destination}")
        fetch_git_repo(destination, revision, fetch_url, timeout=fetch_timeout, attempts=fetch_attempts)
        run(("git", "checkout", "--detach", "FETCH_HEAD"), cwd=destination)
        current = git_output(destination, "rev-parse", "HEAD")
        created = True
    dirty = git_output(destination, "status", "--porcelain")
    if current != revision:
        if not created and not update:
            raise RuntimeError(
                f"{destination} is at {current}, expected {revision}; rerun with --update"
            )
        if not created and dirty:
            raise RuntimeError(f"refusing to update a dirty dependency: {destination}")
        try:
            git_output(destination, "cat-file", "-e", f"{revision}^{{commit}}")
        except subprocess.CalledProcessError:
            fetch_git_repo(destination, revision, fetch_url, timeout=fetch_timeout, attempts=fetch_attempts)
        run(("git", "checkout", "--detach", revision), cwd=destination)
    elif dirty and not allow_dirty:
        raise RuntimeError(f"pinned dependency has local changes: {destination}")

    if recursive:
        command: tuple[str, ...] = ("git", "submodule", "update", "--init", "--depth", "1")
        if submodules:
            command += ("--", *submodules)
        else:
            command += ("--recursive",)
        run(command, cwd=destination)
    print(f"[dependency] {destination.name}: {revision}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_file(
    url: str,
    destination: Path,
    expected_sha256: str,
    *,
    update: bool = False,
    retries: int = 3,
    timeout: int = 30,
    resume: bool = False,
) -> None:
    destination = destination.resolve()
    if destination.is_file():
        actual = sha256(destination)
        if actual == expected_sha256:
            print(f"[dependency] archive verified: {destination}")
            return
        if not update:
            raise RuntimeError(
                f"checksum mismatch for {destination}: {actual}; rerun with --update"
            )

    destination.parent.mkdir(parents=True, exist_ok=True)
    last_error: Exception | None = None
    partial = destination.with_name(f".{destination.name}.partial") if resume else None
    for attempt in range(1, retries + 1):
        if partial is None:
            fd, temporary_name = tempfile.mkstemp(
                prefix=f".{destination.name}.", dir=destination.parent
            )
            os.close(fd)
            temporary = Path(temporary_name)
        else:
            temporary = partial
        try:
            received = temporary.stat().st_size if temporary.is_file() else 0
            headers = {"User-Agent": "retroSoC-setup/1"}
            if received:
                headers["Range"] = f"bytes={received}-"
            request = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(request, timeout=timeout) as response:
                append = received != 0 and response.status == 206
                with temporary.open("ab" if append else "wb") as output:
                    while chunk := response.read(1024 * 1024):
                        output.write(chunk)
            actual = sha256(temporary)
            if actual != expected_sha256:
                if resume:
                    temporary.unlink(missing_ok=True)
                raise RuntimeError(
                    f"checksum mismatch for {url}: {actual}, expected {expected_sha256}"
                )
            os.replace(temporary, destination)
            print(f"[dependency] downloaded: {destination}")
            return
        except Exception as error:
            last_error = error
            if not resume:
                temporary.unlink(missing_ok=True)
            if attempt < retries:
                time.sleep(attempt)
    raise RuntimeError(f"failed to download {url}: {last_error}")


def download_file_from_urls(
    urls: Iterable[str],
    destination: Path,
    expected_sha256: str,
    *,
    update: bool = False,
    retries: int = 3,
    timeout: int = 30,
    resume: bool = False,
) -> None:
    candidates = tuple(urls)
    if not candidates:
        raise ValueError("at least one download URL is required")
    failures: list[str] = []
    for url in candidates:
        try:
            download_file(
                url,
                destination,
                expected_sha256,
                update=update,
                retries=retries,
                timeout=timeout,
                resume=resume,
            )
            return
        except RuntimeError as error:
            failures.append(str(error))
            print(f"[dependency] mirror failed: {url}: {error}")
    raise RuntimeError("all download mirrors failed: " + "; ".join(failures))


def atomic_write(path: Path, content: str) -> bool:
    path = path.resolve()
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
        os.replace(temporary_name, path)
    except Exception:
        Path(temporary_name).unlink(missing_ok=True)
        raise
    return True
