import json, urllib.request, urllib.parse
def get(path):
    return json.loads(urllib.request.urlopen("https://api.deezer.com/" + path, timeout=20).read())
gid=7411938
q=urllib.parse.quote('artist:"glaive"')
listed={a["id"]:a["title"] for a in get(f"artist/{gid}/albums?limit=100")["data"]}
searched={a["id"]:a["title"] for a in get(f"search/album?q={q}&limit=100")["data"] if a["artist"]["id"]==gid}
songs=get(f"search/track?q={q}&limit=100")["data"]
top=get(f"artist/{gid}/top?limit=50")["data"]
fromsongs={t["album"]["id"]:t["album"]["title"] for t in songs+top if t["artist"]["id"]==gid}
merged=dict(listed); merged.update(searched); merged.update(fromsongs)
print("RESULT listed", len(listed), "searched", len(searched), "fromsongs", len(fromsongs), "merged", len(merged))
print("RESULT has Asheghanistan:", 1141203311 in merged, "| extra titles:", sorted(set(merged.values())-set(listed.values())))
print("RESULT songs search total:", len(songs), [t["title"] for t in songs if "ashegh" in t["title"].lower()])
