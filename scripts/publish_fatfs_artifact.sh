#!/usr/bin/env bash
# Publish the archive pinned by config/dependencies.lock.json to retroSoC/artifact.

set -euo pipefail

readonly REPOSITORY="retroSoC/artifact"
readonly RELEASE_TAG="fatfs-r0.16"
readonly ASSET_NAME="fatfs-r0.16.zip"
readonly ARCHIVE_SHA256="99f7dc1f7e095356e4a9e3dbe29959090d8b948afe2bbc5441e52fdf4b85449e"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SOURCE_ARCHIVE="${1:-${ROOT_DIR}/app/fatfs/ff16/ff16.zip}"

command -v gh >/dev/null
gh auth status --hostname github.com

if [[ ! -f "${SOURCE_ARCHIVE}" ]]; then
    printf 'FatFs archive not found: %s\n' "${SOURCE_ARCHIVE}" >&2
    exit 1
fi

actual_sha256="$(sha256sum "${SOURCE_ARCHIVE}" | awk '{print $1}')"
if [[ "${actual_sha256}" != "${ARCHIVE_SHA256}" ]]; then
    printf 'FatFs archive checksum mismatch: expected %s, got %s\n' \
        "${ARCHIVE_SHA256}" "${actual_sha256}" >&2
    exit 1
fi

if gh release view "${RELEASE_TAG}" --repo "${REPOSITORY}" >/dev/null 2>&1; then
    printf 'Release already exists: %s\n' "${RELEASE_TAG}" >&2
    exit 1
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "${temporary_dir}"' EXIT
publish_archive="${temporary_dir}/${ASSET_NAME}"
cp "${SOURCE_ARCHIVE}" "${publish_archive}"

gh release create "${RELEASE_TAG}" --repo "${REPOSITORY}" --title "FatFs R0.16" \
    --notes "Locked FatFs R0.16 source archive." "${publish_archive}"
gh release download "$RELEASE_TAG" --repo "$REPOSITORY" --pattern "$ASSET_NAME" \
    --dir "${temporary_dir}/download"

published_sha256="$(sha256sum "${temporary_dir}/download/${ASSET_NAME}" | awk '{print $1}')"
if [[ "${published_sha256}" != "${ARCHIVE_SHA256}" ]]; then
    printf 'Published FatFs archive checksum mismatch: expected %s, got %s\n' \
        "${ARCHIVE_SHA256}" "${published_sha256}" >&2
    exit 1
fi

printf 'Published https://github.com/%s/releases/download/%s/%s\n' \
    "${REPOSITORY}" "${RELEASE_TAG}" "${ASSET_NAME}"
