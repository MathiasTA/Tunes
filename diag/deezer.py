import json, urllib.request
def get(path):
    return json.loads(urllib.request.urlopen("https://api.deezer.com/" + path, timeout=20).read())
albums = get("artist/7411938/albums?limit=100")["data"]
ids = [a["id"] for a in albums]
print("RESULT single in discography:", 1141203311 in ids)
print("RESULT newest by date:", sorted([(a.get("release_date"), a["title"], a.get("record_type")) for a in albums])[-4:])
al = get("album/1141203311")
print("RESULT album:", al.get("title"), al.get("record_type"), al.get("release_date"), "artist:", al["artist"]["name"], al["artist"]["id"],
      "contributors:", [(c["name"], c["id"]) for c in al.get("contributors", [])], "available:", al.get("available"))
