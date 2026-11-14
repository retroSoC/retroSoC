# Python Tool Requirements

This directory contains pinned Python requirement sets used by repository
automation.

- `build.txt` provides dependencies for setup, build, and regression helpers.
- `ci.txt` provides the fast quality tools, including Python lint and test
  dependencies.
- `rtthread.txt` pins SCons for the isolated HP RT-Thread build environment.

Update requirements deliberately and keep their hashes/pins compatible with
the repository lock policy. Validate the affected commands locally and in CI;
do not add unpinned runtime downloads to scripts.

- publication.txt is the isolated, fully hash-pinned environment for CPython
  3.10/Linux x86_64 and 3.12/Windows x86_64. It contains Matplotlib 3.10.7 and
  its numerical/font/PDF dependencies with the complete transitive wheel closure.
  Install with python -m pip install --require-hashes -r requirements/publication.txt.
  See [publication maintenance](../publications/specifications/README.md).
