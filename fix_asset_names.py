#!/usr/bin/env python3
"""에셋 카탈로그 정리 스크립트 (빌드 전에 실행)
1) 이미지 파일명의 특수문자(U+202F 등)를 ASCII로 변경하고 Contents.json도 맞춤
2) lab/, buildings_home/, equipment/ 안의 대문자 이미지셋 이름을 소문자로 변경
   (코드는 'lab/barbarian' 처럼 소문자로 찾는데 저장소에는 'Barbarian'으로 올라가 있어서 이미지가 안 나옴)
사용법: python3 fix_asset_names.py clash_widgets/Assets.xcassets
"""
import json, os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else "clash_widgets/Assets.xcassets"

# ---- 1) 파일명 특수문자 정리 ----
bad = re.compile(r"#U[0-9a-fA-F]{4}|[^\x20-\x7E]")
fixed = 0
for d, _, _ in os.walk(root):
    if not d.endswith(".imageset"):
        continue
    cj = os.path.join(d, "Contents.json")
    if not os.path.exists(cj):
        continue
    with open(cj, encoding="utf-8") as f:
        data = json.load(f)
    changed = False
    on_disk = os.listdir(d)
    for im in data.get("images", []):
        fn = im.get("filename")
        if not fn or (not bad.search(fn) and fn in on_disk):
            continue
        new = bad.sub("_", fn)
        candidates = [fn, re.sub(r"[^\x20-\x7E]", lambda m: "#U%04x" % ord(m.group()), fn)]
        src = next((c for c in candidates if c in on_disk), None)
        if src is None:
            print("not found:", d, fn)
            continue
        if src != new:
            os.rename(os.path.join(d, src), os.path.join(d, new))
        im["filename"] = new
        changed = True
        fixed += 1
        print("fixed filename:", d, "->", new)
    if changed:
        with open(cj, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
print("filenames fixed:", fixed)

# ---- 2) 대문자 이미지셋 이름을 소문자로 ----
renamed = 0
for folder in ("lab", "buildings_home", "equipment"):
    base = os.path.join(root, folder)
    if not os.path.isdir(base):
        continue
    for name in sorted(os.listdir(base)):
        if not name.endswith(".imageset") or name == name.lower():
            continue
        src = os.path.join(base, name)
        dst = os.path.join(base, name.lower())
        tmp = src + ".tmp_rename"
        os.rename(src, tmp)      # 대소문자 구분 없는 파일시스템(macOS)에서도 안전하게 이름 변경
        os.rename(tmp, dst)
        renamed += 1
        print("renamed:", name, "->", name.lower())
print("imagesets renamed:", renamed)
