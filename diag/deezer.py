import json, urllib.request, urllib.parse
def get(path):
    return json.loads(urllib.request.urlopen("https://api.deezer.com/" + path, timeout=20).read())
r = get("search/track?q=" + urllib.parse.quote("asheghanistan") + "&limit=5")
for t in r.get("data", []):
    full = get(f"track/{t['id']}")
    print("TRACK", t["id"], t["title"], "| main:", t["artist"]["name"], t["artist"]["id"],
          "| contributors:", [(c["name"], c["id"], c.get("role")) for c in full.get("contributors", [])],
          "| album:", t["album"]["id"], t["album"]["title"], "| release:", full.get("release_date"))
a = get("search/artist?q=glaive&limit=5")
for x in a.get("data", []):
    print("ARTIST", x["id"], x["name"], "albums:", x.get("nb_album"), "fans:", x.get("nb_fan"))
gid = a["data"][0]["id"]
albums = get(f"artist/{gid}/albums?limit=100")
print("GLAIVE ALBUMS total:", albums.get("total"), "returned:", len(albums.get("data", [])))
for al in albums.get("data", [])[:12]:
    print("ALB", al["id"], al["title"], al.get("record_type"), al.get("release_date"))
