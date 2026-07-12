# Python Tool Requirements

This directory contains pinned Python requirement sets used by repository
automation.

- `build.txt` provides dependencies for setup, build, and regression helpers.
- `ci.txt` provides the fast quality tools, including Python lint and test
  dependencies.

Update requirements deliberately and keep their hashes/pins compatible with
the repository lock policy. Validate the affected commands locally and in CI;
do not add unpinned runtime downloads to scripts.
