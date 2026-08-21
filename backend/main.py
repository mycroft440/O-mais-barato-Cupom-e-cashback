from __future__ import annotations

import asyncio, hashlib, json, math, os, re, statistics, time, unicodedata
from typing import Any
from urllib.parse import urlparse, urlunparse

import httpx
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="O Mais Barato API", version="0.4.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=False, allow_methods=["GET"], allow_headers=["*"])

ML_API = "https://api.mercadolibre.com"
SHOPEE_API = "https://open-api.affiliate.shopee.com.br/graphql"
AMAZON_TOKEN = "https://api.amazon.com/auth/o2/token"
AMAZON_API = "https://creatorsapi.amazon/catalog/v1/searchItems"
AMAZON_MARKETPLACE = "www.amazon.com.br"
_amz_cache: dict[str, Any] = {"token": None, "expires": 0.0}
STOP = {"a","as","o","os","de","da","do","das","dos","e","para","com","sem","em","por","produto","original","oficial","novo","nova","promocao","promo","oferta","frete","gratis","brasil","masculino","feminino","unissex"}


def env(name: str) -> str: return os.getenv(name, "").strip()
def money(v: Any) -> float:
    try: return round(float(v), 2)
    except (TypeError, ValueError): return 0.0

def median(v: list[float]) -> float | None:
    v = [x for x in v if x > 0]
    return round(float(statistics.median(v)), 2) if v else None

def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c)).lower()
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", s)).strip()

def toks(s: str) -> set[str]: return {x for x in norm(s).split() if len(x) > 1 and x not in STOP}
def digit_toks(s: str) -> set[str]: return {x for x in toks(s) if any(c.isdigit() for c in x)}
def gtins(o: dict[str, Any]) -> set[str]:
    vals: list[str] = []
    ids = o.get("external_ids") or {}
    if isinstance(ids, dict):
        for k in ("gtin","ean","eans","gtins"):
            v = ids.get(k)
            vals += [str(x) for x in v] if isinstance(v, list) else ([str(v)] if v else [])
    out: set[str] = set()
    for v in vals: out.update(re.findall(r"\b\d{8,14}\b", v))
    return out


def equivalent(a: dict[str, Any], b: dict[str, Any]) -> bool:
    ga, gb = gtins(a), gtins(b)
    if ga and gb: return bool(ga & gb)
    ba, bb = norm(str(a.get("brand") or "")), norm(str(b.get("brand") or ""))
    if ba and bb and ba != bb: return False
    ta, tb = toks(str(a.get("name") or "")), toks(str(b.get("name") or ""))
    if not ta or not tb: return False
    da, db = digit_toks(str(a.get("name") or "")), digit_toks(str(b.get("name") or ""))
    if da and db and da != db: return False
    inter, union = len(ta & tb), len(ta | tb)
    return (inter / union >= (0.58 if (da or db) else 0.76)) or (inter / min(len(ta), len(tb)) >= 0.82)


def popularity(sales: int = 0, position: int | None = None, rank: int | None = None) -> float:
    if sales > 0: return min(100.0, math.log1p(sales) * 9)
    if position: return max(1.0, 100 - min(position, 50) * 1.8)
    return max(1.0, 55 - rank) if rank else 0.0


def connector_status() -> dict[str, dict[str, Any]]:
    return {
        "mercadolivre": {"configured": bool(env("MERCADOLIVRE_ACCESS_TOKEN")), "mode": "catalog_api", "affiliate_links": False},
        "shopee": {"configured": bool(env("SHOPEE_AFFILIATE_APP_ID") and env("SHOPEE_AFFILIATE_SECRET")), "mode": "affiliate_open_api", "affiliate_links": True},
        "amazon": {"configured": bool(env("AMAZON_CREATORS_CREDENTIAL_ID") and env("AMAZON_CREATORS_CREDENTIAL_SECRET") and env("AMAZON_PARTNER_TAG")), "mode": "creators_api", "affiliate_links": True},
        "magalu": {"configured": bool(env("MAGALU_FEED_URL")), "mode": "authorized_feed", "affiliate_links": bool(env("MAGALU_STORE_SLUG"))},
    }


async def ml_get(c: httpx.AsyncClient, path: str, params=None, allow_404=False) -> dict[str, Any]:
    r = await c.get(ML_API + path, params=params, headers={"Authorization": f"Bearer {env('MERCADOLIVRE_ACCESS_TOKEN')}"}, timeout=12)
    if allow_404 and r.status_code == 404: return {}
    r.raise_for_status(); return r.json()

def ml_attr(p: dict[str, Any], aid: str) -> str:
    for a in p.get("attributes") or []:
        if a.get("id") == aid: return str(a.get("value_name") or ((a.get("values") or [{}])[0].get("name")) or "")
    return ""

async def search_ml(q: str, limit: int) -> list[dict[str, Any]]:
    if not connector_status()["mercadolivre"]["configured"]: return []
    async with httpx.AsyncClient() as c:
        data = await ml_get(c, "/products/search", {"status":"active","site_id":"MLB","q":q,"limit":min(max(limit*2,10),40)})
        sem = asyncio.Semaphore(6)
        async def one(p: dict[str, Any], rank: int):
            async with sem:
                pid = str(p.get("id") or "")
                if not pid: return None
                try:
                    items, hi = await asyncio.gather(ml_get(c, f"/products/{pid}/items"), ml_get(c, f"/highlights/MLB/product/{pid}", allow_404=True))
                except httpx.HTTPError: return None
                ls = [x for x in items.get("results") or [] if money(x.get("price")) > 0 and x.get("condition") in (None,"new")]
                if not ls: return None
                ls.sort(key=lambda x: money(x.get("price"))); w = ls[0]; price = money(w.get("price"))
                pos = hi.get("position"); pos = int(pos) if isinstance(pos, int) else None
                pics = p.get("pictures") or []; image = (pics[0].get("secure_url") or pics[0].get("url")) if pics and isinstance(pics[0],dict) else None
                gtin = ml_attr(p,"GTIN") or ml_attr(p,"EAN"); url = p.get("permalink") or f"https://www.mercadolivre.com.br/p/{pid}"
                return {"id":str(w.get("item_id") or pid),"source_id":str(w.get("item_id") or pid),"catalog_product_id":pid,"name":str(p.get("name") or p.get("family_name") or "Produto"),"category":str(p.get("domain_id") or ""),"brand":ml_attr(p,"BRAND"),"marketplace":"Mercado Livre","seller":str(w.get("seller_id") or ""),"price":price,"original_price":price,"comparison_price":median([money(x.get("price")) for x in ls[1:]]),"compared_listings":len(ls),"image_url":image,"product_url":url,"affiliate_url":url,"affiliate_ready":False,"sales":0,"rating":None,"popularity_position":pos,"popularity_score":popularity(position=pos,rank=rank),"external_ids":{"gtin":gtin} if gtin else {},"source":"mercadolivre"}
        rows = await asyncio.gather(*(one(p,i+1) for i,p in enumerate(data.get("results") or [])))
        return [x for x in rows if x][:limit]


def shopee_payload(q: str, limit: int) -> str:
    gql = """query ProductOffer($keyword:String,$page:Int,$limit:Int){productOfferV2(keyword:$keyword,sortType:2,page:$page,limit:$limit){nodes{itemId productName productLink offerLink imageUrl priceMin priceMax priceDiscountRate sales ratingStar commissionRate shopId shopName shopType periodStartTime periodEndTime} pageInfo{page limit hasNextPage}}}"""
    return json.dumps({"query":gql,"variables":{"keyword":q,"page":1,"limit":min(limit,50)}},ensure_ascii=False,separators=(",",":"))

async def search_shopee(q: str, limit: int) -> list[dict[str, Any]]:
    app_id, secret = env("SHOPEE_AFFILIATE_APP_ID"), env("SHOPEE_AFFILIATE_SECRET")
    if not (app_id and secret): return []
    payload = shopee_payload(q,limit); ts = int(time.time()); sig = hashlib.sha256(f"{app_id}{ts}{payload}{secret}".encode()).hexdigest()
    h = {"Content-Type":"application/json","Accept":"application/json","Authorization":f"SHA256 Credential={app_id}, Timestamp={ts}, Signature={sig}"}
    async with httpx.AsyncClient() as c:
        r = await c.post(SHOPEE_API,content=payload.encode(),headers=h,timeout=20); r.raise_for_status(); body=r.json()
    if body.get("errors"): raise RuntimeError(f"Shopee API: {body['errors'][0].get('message','erro GraphQL')}")
    out=[]
    for rank,n in enumerate((((body.get("data") or {}).get("productOfferV2") or {}).get("nodes") or []),1):
        price=money(n.get("priceMin"));
        if price<=0: continue
        d=money(n.get("priceDiscountRate")); d=d*100 if 0<d<1 else d; original=round(price/(1-d/100),2) if 0<d<100 else price; sales=int(money(n.get("sales")))
        out.append({"id":f"shopee:{n.get('shopId')}:{n.get('itemId')}","source_id":str(n.get("itemId") or ""),"catalog_product_id":None,"name":str(n.get("productName") or "Produto Shopee"),"category":"Shopee","brand":"","marketplace":"Shopee","seller":str(n.get("shopName") or ""),"price":price,"original_price":original,"comparison_price":None,"compared_listings":1,"image_url":n.get("imageUrl"),"product_url":n.get("productLink"),"affiliate_url":n.get("offerLink") or n.get("productLink"),"affiliate_ready":bool(n.get("offerLink")),"sales":sales,"rating":money(n.get("ratingStar")) or None,"popularity_position":None,"popularity_score":popularity(sales=sales,rank=rank),"commission_rate":money(n.get("commissionRate")),"external_ids":{},"source":"shopee"})
    return out[:limit]


async def amazon_token() -> str:
    now=time.time()
    if _amz_cache["token"] and _amz_cache["expires"]>now+60: return str(_amz_cache["token"])
    async with httpx.AsyncClient() as c:
        r=await c.post(AMAZON_TOKEN,json={"grant_type":"client_credentials","client_id":env("AMAZON_CREATORS_CREDENTIAL_ID"),"client_secret":env("AMAZON_CREATORS_CREDENTIAL_SECRET"),"scope":"creatorsapi::default"},timeout=15); r.raise_for_status(); d=r.json()
    _amz_cache.update(token=str(d["access_token"]),expires=now+int(d.get("expires_in") or 3600)); return str(_amz_cache["token"])

def amazon_brand(i: dict[str, Any]) -> str:
    b=((i.get("itemInfo") or {}).get("byLineInfo") or {})
    for k in ("brand","manufacturer"):
        v=b.get(k)
        if isinstance(v,dict) and v.get("displayValue"): return str(v["displayValue"])
    return ""
def amazon_eans(i: dict[str, Any]) -> list[str]:
    e=((i.get("itemInfo") or {}).get("externalIds") or {})
    for k in ("eans","ean"):
        v=e.get(k)
        if isinstance(v,dict): return [str(x) for x in v.get("displayValues") or []]
    return []

async def search_amazon(q: str, limit: int) -> list[dict[str, Any]]:
    if not connector_status()["amazon"]["configured"]: return []
    token=await amazon_token(); tag=env("AMAZON_PARTNER_TAG")
    payload={"keywords":q,"searchIndex":"All","itemCount":min(limit,10),"marketplace":AMAZON_MARKETPLACE,"partnerTag":tag,"resources":["images.primary.medium","itemInfo.title","itemInfo.byLineInfo","itemInfo.externalIds","offersV2.listings.price","offersV2.listings.merchantInfo"]}
    async with httpx.AsyncClient() as c:
        r=await c.post(AMAZON_API,json=payload,headers={"Authorization":f"Bearer {token}","Content-Type":"application/json","x-marketplace":AMAZON_MARKETPLACE},timeout=20); r.raise_for_status(); body=r.json()
    out=[]
    for rank,i in enumerate(((body.get("searchResult") or {}).get("items") or []),1):
        ls=[]
        for x in ((i.get("offersV2") or {}).get("listings") or []):
            p=money((((x.get("price") or {}).get("money")) or {}).get("amount"))
            if p>0: ls.append((p,x))
        if not ls: continue
        ls.sort(key=lambda x:x[0]); price,l=ls[0]; pd=l.get("price") or {}; original=money((((pd.get("savingBasis") or {}).get("money")) or {}).get("amount")) or price; asin=str(i.get("asin") or ""); url=i.get("detailPageURL")
        out.append({"id":f"amazon:{asin}","source_id":asin,"catalog_product_id":asin,"name":str((((i.get("itemInfo") or {}).get("title") or {}).get("displayValue")) or "Produto Amazon"),"category":"Amazon","brand":amazon_brand(i),"marketplace":"Amazon","seller":str((l.get("merchantInfo") or {}).get("name") or "Amazon"),"price":price,"original_price":original,"comparison_price":median([x[0] for x in ls[1:]]),"compared_listings":max(1,len(ls)),"image_url":((((i.get("images") or {}).get("primary") or {}).get("medium") or {}).get("url")),"product_url":url,"affiliate_url":url,"affiliate_ready":bool(url and tag),"sales":0,"rating":None,"popularity_position":None,"popularity_score":popularity(rank=rank),"external_ids":{"ean":amazon_eans(i),"asin":asin},"source":"amazon"})
    return out[:limit]


def first(d: dict[str, Any], *keys: str) -> Any:
    for k in keys:
        if d.get(k) not in (None,""): return d[k]
    return None

def magalu_url(url: str | None) -> str | None:
    slug=env("MAGALU_STORE_SLUG")
    if not url or not slug: return url
    p=urlparse(url); host=p.netloc.lower(); parts=[x for x in p.path.split("/") if x]
    if "magazinevoce.com.br" in host and parts: parts=parts[1:]
    elif "magazineluiza.com.br" not in host and "magalu.com" not in host: return url
    return urlunparse(("https","www.magazinevoce.com.br","/"+"/".join([slug,*parts]),"",p.query,""))

async def search_magalu(q: str, limit: int) -> list[dict[str, Any]]:
    url=env("MAGALU_FEED_URL")
    if not url: return []
    h={"Accept":"application/json"}; token=env("MAGALU_FEED_TOKEN")
    if token: h["Authorization"]=f"Bearer {token}"
    qp=env("MAGALU_FEED_QUERY_PARAM"); params={qp:q} if qp else None
    async with httpx.AsyncClient() as c:
        r=await c.get(url,headers=h,params=params,timeout=25); r.raise_for_status(); body=r.json()
    items=body if isinstance(body,list) else (body.get("results") or body.get("products") or body.get("items") or body.get("data") or [])
    if isinstance(items,dict): items=items.get("items") or items.get("products") or []
    if not isinstance(items,list): return []
    out=[]; qt=toks(q)
    for rank,x in enumerate(items,1):
        if not isinstance(x,dict): continue
        name=str(first(x,"name","title","productName","product_name") or "")
        if qt and not qt.issubset(toks(name)): continue
        price=money(first(x,"price","salePrice","sale_price","current_price"))
        if price<=0: continue
        original=money(first(x,"originalPrice","listPrice","list_price","original_price")) or price; purl=first(x,"productUrl","product_url","url","link"); sales=int(money(first(x,"sales","sold","soldCount","sold_count"))); iid=str(first(x,"id","sku","productId","product_id") or f"magalu-{rank}"); gtin=first(x,"gtin","ean","barcode")
        out.append({"id":f"magalu:{iid}","source_id":iid,"catalog_product_id":str(first(x,"groupId","group_id","productId","product_id") or iid),"name":name or "Produto Magalu","category":str(first(x,"category","categoryName","category_name") or "Magalu"),"brand":str(first(x,"brand","brandName","brand_name") or ""),"marketplace":"Magalu","seller":str(first(x,"seller","sellerName","seller_name") or "Magalu"),"price":price,"original_price":original,"comparison_price":None,"compared_listings":1,"image_url":first(x,"imageUrl","image_url","image","thumbnail"),"product_url":purl,"affiliate_url":magalu_url(str(purl)) if purl else None,"affiliate_ready":bool(purl and env("MAGALU_STORE_SLUG")),"sales":sales,"rating":money(first(x,"rating","ratingStar","rating_star")) or None,"popularity_position":None,"popularity_score":popularity(sales=sales,rank=rank),"external_ids":{"gtin":str(gtin)} if gtin else {},"source":"magalu"})
        if len(out)>=limit: break
    return out


CONNECTORS={"mercadolivre":search_ml,"shopee":search_shopee,"amazon":search_amazon,"magalu":search_magalu}


def group_equivalent(offers: list[dict[str, Any]]) -> list[list[dict[str, Any]]]:
    groups=[]
    for o in sorted(offers,key=lambda x:-float(x.get("popularity_score") or 0)):
        for g in groups:
            if any(equivalent(o,e) for e in g): g.append(o); break
        else: groups.append([o])
    return groups

def canonical_id(g: list[dict[str, Any]]) -> str:
    all_gtin=sorted(set().union(*(gtins(o) for o in g)))
    if all_gtin: return f"gtin:{all_gtin[0]}"
    b=max(g,key=lambda o:len(str(o.get("name") or ""))); basis=f"{norm(str(b.get('brand') or ''))}|{' '.join(sorted(toks(str(b.get('name') or ''))))}"
    return "match:"+hashlib.sha1(basis.encode()).hexdigest()[:16]
def winner(g: list[dict[str, Any]]) -> dict[str, Any]:
    ordered=sorted(g,key=lambda o:money(o.get("price"))); w=dict(ordered[0]); peers=[]
    for o in ordered[1:]:
        peers.append(money(o.get("price"))); ref=money(o.get("comparison_price")); peers += [ref] if ref>0 else []
    ref=money(w.get("comparison_price")); peers += [ref] if ref>0 else []; cp=median(peers); p=money(w.get("price")); save=round((1-p/cp)*100,2) if cp and p<cp else 0.0; display=max(g,key=lambda o:len(str(o.get("name") or "")))
    w.update(canonical_product_id=canonical_id(g),name=display.get("name") or w.get("name"),brand=w.get("brand") or display.get("brand") or "",image_url=w.get("image_url") or display.get("image_url"),comparison_price=cp,compared_listings=sum(max(1,int(o.get("compared_listings") or 1)) for o in g),compared_sources=sorted({str(o.get("marketplace")) for o in g if o.get("marketplace")}),savings_vs_peers_percent=save,popularity_score=max(float(o.get("popularity_score") or 0) for o in g),alternatives=[{"marketplace":o.get("marketplace"),"seller":o.get("seller"),"price":money(o.get("price")),"product_url":o.get("product_url"),"affiliate_url":o.get("affiliate_url"),"affiliate_ready":bool(o.get("affiliate_ready"))} for o in ordered[:6]])
    return w

async def search_all(q: str, limit: int, requested: set[str] | None):
    st=connector_status(); active=[n for n in CONNECTORS if st[n]["configured"] and (requested is None or n in requested)]; errors={}
    async def run(n):
        try: return await CONNECTORS[n](q,max(limit*2,12))
        except Exception as e: errors[n]=str(e)[:300]; return []
    batches=await asyncio.gather(*(run(n) for n in active)); offers=[o for b in batches for o in b]; out=[winner(g) for g in group_equivalent(offers)]
    out.sort(key=lambda o:(-float(o.get("popularity_score") or 0),-len(o.get("compared_sources") or []),-float(o.get("savings_vs_peers_percent") or 0),money(o.get("price"))))
    return out,errors

def parse_sources(raw: str | None):
    return None if not raw else {x.strip().lower() for x in raw.split(",") if x.strip().lower() in CONNECTORS}

@app.get("/health")
async def health(): return {"status":"ok","connectors":connector_status()}
@app.get("/connectors")
async def connectors(): return {"connectors":connector_status()}
@app.get("/search")
async def search(q:str=Query(min_length=2,max_length=120),limit:int=Query(12,ge=1,le=30),sources:str|None=None,comparable_only:bool=True):
    out,errors=await search_all(q.strip(),limit,parse_sources(sources)); out=[x for x in out if int(x.get("compared_listings") or 1)>=2] if comparable_only else out
    return {"query":q,"comparison_rule":"lowest_price_per_equivalent_product_no_minimum_discount","connectors":connector_status(),"errors":errors,"results":out[:limit]}
@app.get("/feed")
async def feed(q:str=Query("ofertas",min_length=2,max_length=120),limit:int=Query(12,ge=1,le=30),sources:str|None=None):
    out,errors=await search_all(q.strip(),limit,parse_sources(sources)); out=[x for x in out if int(x.get("compared_listings") or 1)>=2]
    return {"query":q,"comparison_rule":"lowest_price_per_equivalent_product_no_minimum_discount","connectors":connector_status(),"errors":errors,"results":out[:limit]}
