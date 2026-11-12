import sys, re, urllib.request, urllib.parse, html
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"}
def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40).read().decode("utf-8", "replace")
for q in sys.argv[1:]:
    url = "https://freesound.org/search/?" + urllib.parse.urlencode({"q": q, "f": 'license:"Creative Commons 0"', "s": "Rating (highest first)"})
    page = get(url)
    print("==", q)
    seen = set()
    for m in re.finditer(r'data-sound-id="(\d+)"(.*?)</div>\s*</div>', page, re.S):
        pass
    for m in re.finditer(r'href="/people/([^/"]+)/sounds/(\d+)/"[^>]*title="([^"]*)"', page):
        user, sid, title = m.groups()
        if sid in seen: continue
        seen.add(sid)
        dur = re.search(r'data-sound-id="%s".*?data-duration="([\d.]+)"' % sid, page, re.S)
        print("  %s | %s | %s | %ss" % (sid, user, html.unescape(title), dur.group(1)[:5] if dur else "?"))
        if len(seen) >= 12: break
