import json, sys, urllib.request, os
out = sys.argv[1]
ids = sys.argv[2:]
def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "asset-fetch/1.0"})
    return urllib.request.urlopen(req, timeout=120).read()
for i in ids:
    files = json.loads(get("https://api.polyhaven.com/files/" + i))
    info = json.loads(get("https://api.polyhaven.com/info/" + i))
    print(i, "authors:", list(info.get("authors", {}).keys()), "maps:", [k for k in files if k not in ("blend","gltf","mtlx")])
    for key, short in (("Diffuse", "diff"), ("nor_gl", "nor"), ("Rough", "rough")):
        if key not in files:
            print("  MISSING", key); continue
        url = files[key]["1k"]["jpg"]["url"]
        path = os.path.join(out, "%s_%s.jpg" % (i, short))
        if not os.path.exists(path):
            open(path, "wb").write(get(url))
        print("  ", short, os.path.getsize(path))
