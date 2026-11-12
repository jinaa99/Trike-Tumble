import sys, re, json, os, html, urllib.request
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"}
def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
cred_path = os.path.join(out, "credits.json")
credits = json.load(open(cred_path)) if os.path.exists(cred_path) else {}
for sid in sys.argv[2:]:
    if sid in credits and os.path.exists(os.path.join(out, sid + ".mp3")):
        continue
    try:
        page = get("https://freesound.org/s/%s/" % sid).decode("utf-8", "replace")
    except Exception as e:
        print(sid, "PAGE FAIL", e); continue
    cc0 = "creativecommons.org/publicdomain/zero/1.0" in page
    mp3 = re.search(r'https://cdn\.freesound\.org/previews/\d+/%s_\d+-hq\.mp3' % sid, page)
    canon = re.search(r'<link rel="canonical" href="([^"]+)"', page) or re.search(r'property="og:url" content="([^"]+)"', page)
    title = re.search(r'property="og:audio:title" content="([^"]*)"', page) or re.search(r'<title>([^<]*)', page)
    url = canon.group(1) if canon else ""
    user = re.search(r'/people/([^/]+)/', url)
    if not cc0 or not mp3:
        print(sid, "SKIP cc0=%s mp3=%s" % (cc0, bool(mp3))); continue
    open(os.path.join(out, sid + ".mp3"), "wb").write(get(mp3.group(0)))
    credits[sid] = {"title": html.unescape(title.group(1)) if title else "", "author": user.group(1) if user else "?", "url": url, "license": "CC0 1.0"}
    print(sid, "ok", credits[sid]["author"], "|", credits[sid]["title"][:60])
json.dump(credits, open(cred_path, "w"), indent=1)
