#!/usr/bin/env python3
"""写版本号到唯一版本源 AppScope/app.json5（硬性构建规则，见 BUILD_RULES.md）。

用法: python3 tools/ci/write_version.py <versionName> <versionCode>
- versionName = 1.MMDD.NN
- versionCode = 1MMDDNN（buildVersion 使用同一字符串，三者必须同步）
"""
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    ver_name, ver_code = sys.argv[1], sys.argv[2]
    p = Path("AppScope/app.json5")
    s = p.read_text(encoding="utf-8-sig")
    s2 = re.sub(r'("versionCode"\s*:\s*)\d+', r"\g<1>" + ver_code, s)
    s2 = re.sub(r'("versionName"\s*:\s*")[^"]*(")', r"\g<1>" + ver_name + r"\g<2>", s2)
    s2 = re.sub(r'("buildVersion"\s*:\s*")[^"]*(")', r"\g<1>" + ver_code + r"\g<2>", s2)
    if s2 == s:
        print("ERROR: version fields not found in AppScope/app.json5", file=sys.stderr)
        return 1
    p.write_text(s2, encoding="utf-8-sig")
    print(
        f"wrote versionName={ver_name} versionCode={ver_code} "
        f"buildVersion={ver_code} -> AppScope/app.json5"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
