#!/usr/bin/env python3

from __future__ import annotations

import os
import shlex
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


@dataclass
class FileList:
    defines: list[str] = field(default_factory=list)
    incdirs: list[Path] = field(default_factory=list)
    files: list[Path] = field(default_factory=list)
    library_files: list[Path] = field(default_factory=list)
    options: list[str] = field(default_factory=list)

    def extend(self, other: "FileList") -> None:
        self.defines.extend(other.defines)
        self.incdirs.extend(other.incdirs)
        self.files.extend(other.files)
        self.library_files.extend(other.library_files)
        self.options.extend(other.options)

    def deduplicate(self) -> "FileList":
        self.defines = _unique(self.defines)
        self.incdirs = _unique(self.incdirs)
        self.files = _unique(self.files)
        self.library_files = _unique(self.library_files)
        self.options = _unique(self.options)
        return self

    def as_tokens(self) -> list[str]:
        return [
            *self.defines,
            *(_quote(f"+incdir+{path}") for path in self.incdirs),
            *(item for path in self.library_files for item in ("-v", _quote(str(path)))),
            *self.options,
            *(_quote(str(path)) for path in self.files),
        ]


def _unique(values: Iterable):
    return list(dict.fromkeys(values))


def _quote(value: str) -> str:
    if not any(character.isspace() for character in value):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def atomic_write(path: Path, content: str) -> bool:
    """Write content atomically and preserve mtime when content is unchanged."""
    path = Path(path)
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return False

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
            stream.write(content)
        os.replace(temp_name, path)
    except Exception:
        Path(temp_name).unlink(missing_ok=True)
        raise
    return True


def tokenize_filelist(path: Path) -> list[str]:
    tokens: list[str] = []
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("//") or stripped.startswith("#"):
            continue
        try:
            lexer = shlex.shlex(raw_line, posix=True)
            lexer.whitespace_split = True
            lexer.quotes = '"'
            tokens.extend(lexer)
        except ValueError as error:
            raise ValueError(f"{path}:{line_number}: {error}") from error
    return tokens


def parse_filelists(paths: Iterable[Path], *, require_files: bool = True) -> FileList:
    result = FileList()
    visited: set[Path] = set()
    for path in paths:
        result.extend(
            _parse_filelist(Path(path).resolve(), visited, require_files=require_files)
        )
    return result.deduplicate()


def _parse_filelist(
    path: Path, visited: set[Path], *, require_files: bool
) -> FileList:
    if path in visited:
        return FileList()
    if not path.is_file():
        raise FileNotFoundError(f"filelist not found: {path}")
    visited.add(path)

    result = FileList()
    tokens = tokenize_filelist(path)
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token == "-f":
            index += 1
            if index >= len(tokens):
                raise ValueError(f"{path}: -f requires a filelist path")
            nested = _resolve(tokens[index], path.parent)
            result.extend(
                _parse_filelist(nested, visited, require_files=require_files)
            )
        elif token.startswith("-f") and len(token) > 2:
            nested = _resolve(token[2:], path.parent)
            result.extend(
                _parse_filelist(nested, visited, require_files=require_files)
            )
        elif token.startswith("+define+"):
            result.defines.append(token)
        elif token.startswith("+incdir+"):
            incdir = _resolve(token[len("+incdir+") :], path.parent)
            if require_files and not incdir.is_dir():
                raise FileNotFoundError(f"include directory not found: {incdir}")
            result.incdirs.append(incdir)
        elif token == "-v":
            index += 1
            if index >= len(tokens):
                raise ValueError(f"{path}: -v requires a source path")
            library_file = _resolve(tokens[index], path.parent)
            _require_source(library_file, require_files)
            result.library_files.append(library_file)
        elif token.startswith("-") or token.startswith("+"):
            result.options.append(token)
        else:
            source = _resolve(token, path.parent)
            _require_source(source, require_files)
            result.files.append(source)
        index += 1
    return result


def _resolve(value: str, base: Path) -> Path:
    path = Path(value).expanduser()
    return path.resolve() if path.is_absolute() else (base / path).resolve()


def _require_source(path: Path, required: bool) -> None:
    if required and not path.is_file():
        raise FileNotFoundError(f"source file not found: {path}")


def write_filelist(path: Path, filelist: FileList) -> bool:
    content = "\n".join(filelist.as_tokens()) + "\n"
    return atomic_write(path, content)
