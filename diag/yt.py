import json, urllib.request, collections, sys
def post(client, query, extra=None):
    body={"context":{"client":client},"query":query}
    req=urllib.request.Request("https://www.youtube.com/youtubei/v1/search?prettyPrint=false",data=json.dumps(body).encode(),method="POST",
        headers={"Content-Type":"application/json","Cookie":"SOCS=CAI","User-Agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"})
    try:
        r=urllib.request.urlopen(req,timeout=20); return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e: return e.code, {}
def keys(node, c):
    if isinstance(node,dict):
        for k,v in node.items():
            if k.endswith(("Renderer","ViewModel","Model")): c[k]+=1
            keys(v,c)
    elif isinstance(node,list):
        for v in node: keys(v,c)
for name,client in [("WEB app version",{"clientName":"WEB","clientVersion":"2.20251101.00.00","hl":"en","gl":"US"}),
                    ("WEB DK",{"clientName":"WEB","clientVersion":"2.20251101.00.00","hl":"da","gl":"DK"})]:
    code,data=post(client,"Tobias Rahim - Stor Mand")
    c=collections.Counter(); keys(data,c)
    print(f"== {name}: HTTP {code}, top keys {list(data.keys())[:8]}")
    print("   renderers:", c.most_common(25))
    s=json.dumps(data)
    print("   videoId occurrences:", s.count('"videoId"'), " contentId:", s.count('"contentId"'))
    i=s.find('lockupViewModel')
    if i>=0: print("   lockup sample:", s[i:i+1500])
