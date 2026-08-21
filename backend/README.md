# Backend 24/7

O backend pesquisa várias fontes em paralelo, normaliza os anúncios e retorna o menor preço encontrado para cada produto equivalente. Não existe corte mínimo de 20%, 10% ou qualquer outro percentual.

## Fontes implementadas

### Mercado Livre

Usa a API de catálogo e a lista de anúncios vinculados ao mesmo produto. Dentro do próprio Mercado Livre, o backend já escolhe o menor anúncio antes de comparar com outras lojas.

Variável necessária:

```bash
MERCADOLIVRE_ACCESS_TOKEN=...
```

### Shopee

Usa a Shopee Affiliate Open API (`productOfferV2`) e ordena a coleta por quantidade vendida. O `offerLink` retornado pela API é mantido como `affiliate_url`.

```bash
SHOPEE_AFFILIATE_APP_ID=...
SHOPEE_AFFILIATE_SECRET=...
```

### Amazon

Usa a Amazon Creators API para o marketplace brasileiro. O backend faz OAuth 2.0, reutiliza o token enquanto válido e pesquisa preços, imagens, marca e identificadores externos. A URL retornada pela Creators API já é gerada com a `Partner Tag` configurada.

```bash
AMAZON_CREATORS_CREDENTIAL_ID=...
AMAZON_CREATORS_CREDENTIAL_SECRET=...
AMAZON_PARTNER_TAG=suatag-20
```

### Magalu

A Open API pública do Magalu é voltada principalmente a sellers e integradores, não oferece uma busca pública de afiliados equivalente à Shopee/Amazon. Por isso o conector aceita um **feed/API autorizada** do Parceiro Magalu ou de outro canal oficialmente disponibilizado para sua conta, sem scraping.

```bash
MAGALU_FEED_URL=https://...
MAGALU_FEED_TOKEN=                 # opcional
MAGALU_FEED_QUERY_PARAM=q          # opcional
MAGALU_STORE_SLUG=minhaloja        # opcional; converte URLs para a vitrine Magazine Você
```

O feed pode retornar uma lista JSON diretamente ou um objeto contendo `results`, `products`, `items` ou `data`. O parser aceita campos comuns como `name/title`, `price/salePrice`, `listPrice`, `brand`, `ean/gtin`, `imageUrl` e `productUrl`.

## Comparação entre lojas

O agrupamento usa, nesta ordem:

1. GTIN/EAN quando duas fontes fornecem o identificador;
2. marca;
3. tokens relevantes do nome/modelo;
4. números do modelo/capacidade para impedir, por exemplo, que `Revolution 6` seja comparado com `Revolution 7`.

Para cada grupo o backend:

1. reúne as ofertas equivalentes;
2. ordena pelo preço;
3. escolhe a mais barata mesmo que a diferença seja apenas R$ 1 ou 1%;
4. calcula a diferença percentual apenas como informação;
5. devolve até seis alternativas para auditoria da comparação;
6. ordena os produtos usando os sinais de popularidade disponíveis em cada fonte.

## Endpoints

- `GET /health` — saúde e estado dos conectores;
- `GET /connectors` — mostra quais integrações estão configuradas;
- `GET /search?q=tenis&limit=12` — busca multi-marketplace;
- `GET /feed?q=tenis&limit=12` — feed apenas de produtos com comparação possível.

Parâmetros úteis:

```text
sources=mercadolivre,shopee,amazon,magalu
comparable_only=true
```

A resposta informa `compared_sources`, `compared_listings`, `comparison_price`, `savings_vs_peers_percent`, `affiliate_url` e `alternatives`.

## Segurança

Nunca coloque tokens, secrets ou credenciais de afiliado no Flutter. Eles pertencem ao servidor/secret manager. Use `backend/.env.example` apenas como referência dos nomes das variáveis.
