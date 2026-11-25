#!/usr/bin/env python3
import json, urllib.request, sys, time, os

BASE = "https://api.yeswehack.com/programs"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bounty", "_scopes", "yeswehack.json")


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "research/1.0"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)

def main():
    programs, page = [], 1
    while True:
        data = get(f"{BASE}?page={page}")
        items = data.get("items") or data.get("programs") or []
        if not items: break
        programs.extend(items)
        page += 1
        if page > 6: break
        time.sleep(0.3)

    detailed = []
    for p in programs:
        slug = p.get("slug") or p.get("id")
        if not slug: continue
        try:
            d = get(f"{BASE}/{slug}")
            detailed.append(d)
        except Exception as e:
            detailed.append({"slug": slug, "error": str(e)})
        time.sleep(0.2)

    with open(OUT, "w") as f:
        json.dump(detailed, f, indent=2)
    print(f"[✓] {len(detailed)} program -> {OUT}")

if __name__ == "__main__":
    main()
