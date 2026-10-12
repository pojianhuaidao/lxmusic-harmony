#!/usr/bin/env python3
"""Assemble signed APP bundle and final release zip for lxmusic-harmony CI.

APP 组装必须走官方 app_packing_tool.jar（--mode app），手搓 zip 会被 AGC 报 996。

Usage:
  python3 assemble_bundle.py assemble-app <signed_hap_path> <pack_info_path> <app_tool_jar> <out_app_path>
  python3 assemble_bundle.py bundle-zip <unsigned_hap_path> <app_path_or_dash> <out_zip_path>
"""
import os
import subprocess
import sys
import zipfile


def assemble_app(signed_path, pack_info_path, app_tool_jar, out_path):
    cmd = [
        "java", "-jar", app_tool_jar,
        "--mode", "app",
        "--hap-path", signed_path,
        "--pack-info-path", pack_info_path,
        "--out-path", out_path,
    ]
    print("running app_packing_tool:", " ".join(cmd))
    subprocess.run(cmd, check=True)
    if not os.path.exists(out_path):
        sys.exit("app_packing_tool did not produce output: " + out_path)
    print("signed app built:", out_path, os.path.getsize(out_path), "bytes")


def bundle_zip(unsigned_path, app_path, out_path):
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(unsigned_path, os.path.basename(unsigned_path))
        if app_path != "-" and os.path.exists(app_path):
            z.write(app_path, os.path.basename(app_path))
    print("bundle written:", out_path)


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "assemble-app":
        assemble_app(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif mode == "bundle-zip":
        bundle_zip(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        sys.exit("unknown mode: " + mode)

