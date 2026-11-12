import sys, re, html
for path in sys.argv[1:]:
    t = open(path, encoding="utf-8", errors="replace").read()
    title = re.search(r'<title>([^<]*)', t).group(1)
    author = re.search(r'class="username"[^>]*>([^<]*)', t)
    lic = re.findall(r'license-name[^>]*>([^<]*)', t)
    files = re.findall(r'href="(https://opengameart.org/sites/default/files/[^"]+\.(?:mp3|ogg|wav|zip|flac))"', t)
    body = re.search(r'field-name-body.*?<div class="field-item even"[^>]*>(.*?)</div>', t, re.S)
    desc = re.sub(r'<[^>]+>', ' ', body.group(1)) if body else ''
    print("##", html.unescape(title), "| by", author.group(1) if author else "?", "|", lic)
    print("   ", html.unescape(desc)[:260].replace("\n", " "))
    for f in dict.fromkeys(files): print("    ", f)
