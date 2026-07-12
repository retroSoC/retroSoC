#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path
from typing import Iterable


def run(command: Iterable[str], *, cwd: Path | None = None) -> None:
    printable = " ".join(str(item) for item in command)
    print(f"+ {printable}")
    subprocess.run(
        [str(item) for item in command],
        cwd=cwd,
        check=True,
    )


def git_output(repo: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repo), *args], text=True, stderr=subprocess.STDOUT
    ).strip()


def ensure_git_repo(
    url: str,
    destination: Path,
    revision: str,
    *,
    recursive: bool = False,
    update: bool = False,
    allow_dirty: bool = False,
) -> None:
    destination = destination.resolve()
    created = False
    if not destination.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        run(("git", "init", str(destination)))
        run(("git", "remote", "add", "origin", url), cwd=destination)
        run(("git", "fetch", "--depth", "1", "origin", revision), cwd=destination)
        run(("git", "checkout", "--detach", "FETCH_HEAD"), cwd=destination)
        created = True
    elif not (destination / ".git").exists():
        raise RuntimeError(f"dependency path is not a Git repository: {destination}")

    current = git_output(destination, "rev-parse", "HEAD")
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
            run(("git", "fetch", "--depth", "1", "origin", revision), cwd=destination)
        run(("git", "checkout", "--detach", revision), cwd=destination)
    elif dirty and not allow_dirty:
        raise RuntimeError(f"pinned dependency has local changes: {destination}")

    if recursive:
        run(
            ("git", "submodule", "update", "--init", "--recursive", "--depth", "1"),
            cwd=destination,
        )
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
    for attempt in range(1, retries + 1):
        fd, temporary_name = tempfile.mkstemp(
            prefix=f".{destination.name}.", dir=destination.parent
        )
        os.close(fd)
        temporary = Path(temporary_name)
        try:
            request = urllib.request.Request(
                url, headers={"User-Agent": "retroSoC-setup/1"}
            )
            with urllib.request.urlopen(request, timeout=timeout) as response:
                with temporary.open("wb") as output:
                    while chunk := response.read(1024 * 1024):
                        output.write(chunk)
            actual = sha256(temporary)
            if actual != expected_sha256:
                raise RuntimeError(
                    f"checksum mismatch for {url}: {actual}, expected {expected_sha256}"
                )
            os.replace(temporary, destination)
            print(f"[dependency] downloaded: {destination}")
            return
        except Exception as error:
            last_error = error
            temporary.unlink(missing_ok=True)
            if attempt < retries:
                time.sleep(attempt)
    raise RuntimeError(f"failed to download {url}: {last_error}")


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
