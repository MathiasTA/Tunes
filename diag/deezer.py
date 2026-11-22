import json, urllib.request, urllib.parse
def get(path):
    return json.loads(urllib.request.urlopen("https://api.deezer.com/" + path, timeout=20).read())
for q in ["pardon my french glaive", "pardon my french", 'artist:"glaive" track:"pardon my french"']:
    r = get("search/track?q=" + urllib.parse.quote(q) + "&limit=10")
    print("RESULT track search", repr(q), "->", [(t["title"], t["artist"]["name"], t["album"]["title"]) for t in r.get("data", [])][:6])
r = get("search/album?q=" + urllib.parse.quote("glaive") + "&limit=50")
print("RESULT album search glaive ->", sorted([(a.get("title"), a["artist"]["id"]) for a in r.get("data", []) if a["artist"]["id"] == 7411938])[:60])
top = get("artist/7411938/top?limit=50")
print("RESULT top tracks albums ->", sorted({(t["album"]["title"]) for t in top.get("data", [])}))
