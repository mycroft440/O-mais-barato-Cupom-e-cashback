from __future__ import annotations

import asyncio
import os
import statistics
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="O Mais Barato API",
    version="0.3.0",
    description=(
        "Busca produtos de catálogo e retorna o menor preço encontrado "
        "entre anúncios equivalentes do mesmo produto, sem exigir desconto mínimo."
    ),
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET"],
    allow_headers=["*"],
)

ML_API = "https://api.mercadolibre.com"
SITE_ID = "MLB"


def _token() -> str:
    token = os.getenv("MERCADOLIVRE_ACCESS_TOKEN", "").strip()
    if not token:
        raise HTTPException(
            status_code=503,
            detail=(
                "MERCADOLIVRE_ACCESS_TOKEN não configurado. "
                "Cadastre uma aplicação no Mercado Livre e configure o token no servidor."
            ),
        )
    return token


def _headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {_token()}"}


def _money(value: Any) -> float:
    try:
        return round(float(value), 2)
    except (TypeError, ValueError):
        return 0.0


def _median(values: list[float]) -> float | None:
    positive = [value for value in values if value > 0]
    if not positive:
        return None
    return round(float(statistics.median(positive)), 2)


def _attribute(product: dict[str, Any], attribute_id: str) -> str:
    for attribute in product.get("attributes") or []:
        if attribute.get("id") == attribute_id:
            return str(
                attribute.get("value_name")
                or ((attribute.get("values") or [{}])[0].get("name"))
                or ""
            )
    return ""


async def _get_json(
    client: httpx.AsyncClient,
    path: str,
    *,
    params: dict[str, Any] | None = None,
    allow_404: bool = False,
) -> dict[str, Any]:
    response = await client.get(
        f"{ML_API}{path}",
        params=params,
        headers=_headers(),
        timeout=12,
    )
    if allow_404 and response.status_code == 404:
        return {}
    if response.status_code >= 400:
        raise HTTPException(
            status_code=502,
            detail=f"Mercado Livre respondeu HTTP {response.status_code} em {path}.",
        )
    return response.json()


async def _popularity_position(
    client: httpx.AsyncClient, product_id: str
) -> int | None:
    data = await _get_json(
        client,
        f"/highlights/{SITE_ID}/product/{product_id}",
        allow_404=True,
    )
    position = data.get("position")
    return int(position) if isinstance(position, int) else None


async def _best_listing_for_product(
    client: httpx.AsyncClient,
    product: dict[str, Any],
) -> dict[str, Any] | None:
    product_id = str(product.get("id") or "")
    if not product_id:
        return None

    items_data, popularity = await asyncio.gather(
        _get_json(client, f"/products/{product_id}/items"),
        _popularity_position(client, product_id),
    )

    listings: list[dict[str, Any]] = []
    for raw in items_data.get("results") or []:
        price = _money(raw.get("price"))
        if price <= 0:
            continue
        if raw.get("condition") not in (None, "new"):
            continue
        listings.append(raw)

    if not listings:
        return None

    listings.sort(key=lambda item: _money(item.get("price")))
    winner = listings[0]
    winner_price = _money(winner.get("price"))

    peer_prices = [_money(item.get("price")) for item in listings[1:]]
    comparison_price = _median(peer_prices)
    savings = 0.0
    if comparison_price and winner_price < comparison_price:
        savings = round((1 - winner_price / comparison_price) * 100, 2)

    pictures = product.get("pictures") or []
    image_url = None
    if pictures and isinstance(pictures[0], dict):
        image_url = pictures[0].get("secure_url") or pictures[0].get("url")

    name = str(product.get("name") or product.get("family_name") or "Produto")
    domain_id = str(product.get("domain_id") or "")
    brand = _attribute(product, "BRAND")

    return {
        "id": str(winner.get("item_id") or product_id),
        "item_id": str(winner.get("item_id") or product_id),
        "catalog_product_id": product_id,
        "name": name,
        "category": domain_id,
        "brand": brand,
        "marketplace": "Mercado Livre",
        "seller": str(winner.get("seller_id") or ""),
        "price": winner_price,
        "original_price": winner_price,
        "comparison_price": comparison_price,
        "compared_listings": len(listings),
        "savings_vs_peers_percent": savings,
        "popularity_position": popularity,
        "image_url": image_url,
        "product_url": product.get("permalink"),
        "tags": [token for token in (brand, domain_id) if token],
        "source": "mercadolivre_catalog",
    }


async def _search_marketplace(query: str, limit: int) -> list[dict[str, Any]]:
    async with httpx.AsyncClient() as client:
        catalog = await _get_json(
            client,
            "/products/search",
            params={
                "status": "active",
                "site_id": SITE_ID,
                "q": query,
                "limit": min(max(limit * 2, 10), 40),
            },
        )

        products = list(catalog.get("results") or [])
        if not products:
            return []

        semaphore = asyncio.Semaphore(6)

        async def guarded(product: dict[str, Any]):
            async with semaphore:
                try:
                    return await _best_listing_for_product(client, product)
                except HTTPException:
                    return None
                except httpx.HTTPError:
                    return None

        compared = await asyncio.gather(*(guarded(product) for product in products))
        results = [item for item in compared if item is not None]

    # O produto mais popular vem primeiro. Dentro de posições equivalentes,
    # a economia relativa e o menor preço ajudam no desempate.
    results.sort(
        key=lambda item: (
            item["popularity_position"]
            if item["popularity_position"] is not None
            else 10_000,
            -item["savings_vs_peers_percent"],
            item["price"],
        )
    )
    return results[:limit]


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/search")
async def search(
    q: str = Query(min_length=2, max_length=120),
    limit: int = Query(default=12, ge=1, le=20),
) -> dict[str, Any]:
    results = await _search_marketplace(q.strip(), limit)
    return {
        "query": q,
        "comparison_rule": "lowest_price_per_equivalent_product",
        "results": results,
    }


@app.get("/feed")
async def feed(
    q: str = Query(default="ofertas", min_length=2, max_length=120),
    limit: int = Query(default=12, ge=1, le=20),
) -> dict[str, Any]:
    results = await _search_marketplace(q.strip(), 20)
    comparable = [item for item in results if item["compared_listings"] >= 2]
    return {
        "query": q,
        "comparison_rule": "lowest_price_per_equivalent_product_no_minimum_discount",
        "results": comparable[:limit],
    }
