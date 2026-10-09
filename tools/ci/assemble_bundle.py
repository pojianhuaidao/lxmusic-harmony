#!/usr/bin/env python3
"""Assemble signed APP bundle and final release zip for lxmusic-harmony CI.

Usage:
  python3 assemble_bundle.py assemble-app <signed_hap_path> <out_app_path>
  python3 assemble_bundle.py bundle-zip <unsigned_hap_path> <app_path_or_dash> <out_zip_path>
"""
import os
import sys
import zipfile


def assemble_app(signed_path, out_path):
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(signed_path, "entry-default-signed.hap")
        pack_info = "entry/build/default/outputs/default/pack.info"
        if os.path.exists(pack_info):
            z.write(pack_info, "pack.info")
    print("signed app built:", out_path)


def bundle_zip(unsigned_path, app_path, out_path):
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(unsigned_path, os.path.basename(unsigned_path))
        if app_path != "-" and os.path.exists(app_path):
            z.write(app_path, os.path.basename(app_path))
    print("bundle written:", out_path)


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "assemble-app":
        assemble_app(sys.argv[2], sys.argv[3])
    elif mode == "bundle-zip":
        bundle_zip(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        sys.exit("unknown mode: " + mode)
