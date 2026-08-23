#!/usr/bin/env python
# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

from __future__ import print_function

import argparse
import hashlib
import json
import os
import shutil
import sys
import tarfile


def safe_members(archive, destination):
    root = os.path.realpath(destination)
    for member in archive.getmembers():
        target = os.path.realpath(os.path.join(root, member.name))
        if target != root and not target.startswith(root + os.sep):
            raise ValueError("archive member escapes destination: {0}".format(member.name))
        if member.issym() or member.islnk():
            raise ValueError("archive links are not accepted: {0}".format(member.name))
        if not member.isfile() and not member.isdir():
            raise ValueError(
                "archive special entries are not accepted: {0}".format(member.name)
            )
        yield member


def hash_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            block = handle.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description="Safely stage a commercial RTL input archive")
    parser.add_argument("--archive", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()

    archive_path = os.path.abspath(args.archive)
    output_dir = os.path.abspath(args.output_dir)
    if not tarfile.is_tarfile(archive_path):
        parser.error("RTL archive is not a tar file: {0}".format(archive_path))
    if os.path.isdir(output_dir):
        shutil.rmtree(output_dir)
    os.makedirs(output_dir)
    with tarfile.open(archive_path, "r:*") as archive:
        archive.extractall(output_dir, members=safe_members(archive, output_dir))

    filelist = os.path.join(output_dir, "rtl", "filelist.fl")
    if not os.path.isfile(filelist):
        parser.error("RTL archive does not contain rtl/filelist.fl")
    # Tar extraction preserves the development-zone timestamp. Refresh the
    # staged entry point so the stage runner can distinguish this extraction
    # from output left by an earlier run.
    os.utime(filelist, None)
    manifest = {
        "schema_version": 1,
        "archive_sha256": hash_file(archive_path),
        "filelist": filelist,
    }
    parent = os.path.dirname(os.path.abspath(args.manifest))
    if not os.path.isdir(parent):
        os.makedirs(parent)
    with open(args.manifest, "w") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print("staged RTL input: {0}".format(output_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main())
