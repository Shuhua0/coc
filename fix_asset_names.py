#!/usr/bin/env python3
"""에셋 카탈로그 이미지 파일명에서 특수문자(U+202F 등)를 ASCII로 바꾸고 Contents.json도 같이 맞춰줍니다.
사용법: python3 fix_asset_names.py clash_widgets/Assets.xcassets
"""
import json, os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else "clash_widgets/Assets.xcassets"
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
        if not fn or not bad.search(fn) and fn in on_disk:
            continue
        new = bad.sub("_", fn)
        # 디스크에 있는 실제 파일 찾기 (원래 이름 또는 '#U202f'로 풀린 이름)
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
        print("fixed:", d, "->", new)
    if changed:
        with open(cj, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
print("done, fixed", fixed)
