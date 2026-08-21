# Backend 24/7

O monitoramento contínuo de preços e cupons deve rodar fora do telefone.

## Comparação de preços

A primeira integração real usa produtos de catálogo para evitar comparar itens diferentes.

Para cada produto encontrado:

1. lista os anúncios equivalentes vinculados ao mesmo produto;
2. considera anúncios novos com preço válido;
3. escolhe o anúncio de menor preço;
4. calcula, apenas para informação, a diferença contra a mediana dos demais anúncios;
5. mantém a posição de popularidade quando a fonte fornecer esse dado.

Não há corte mínimo de 20%, 10% ou qualquer outro percentual. O objetivo é sempre mostrar o menor preço encontrado para cada produto.

## Endpoints

- `GET /health`
- `GET /search?q=tenis&limit=12`
- `GET /feed?q=tenis&limit=12`

`/search` e `/feed` retornam o menor anúncio por produto. O `feed` exige apenas que existam pelo menos dois anúncios equivalentes para que a comparação tenha sentido.

## Configuração

Defina no servidor:

```bash
MERCADOLIVRE_ACCESS_TOKEN=...
```

Nunca coloque credenciais de marketplace ou afiliado dentro do aplicativo Flutter.

## Responsabilidades futuras

- receber ofertas de outras lojas e marketplaces;
- normalizar o mesmo produto entre fontes diferentes;
- validar cupons e restrições;
- manter histórico de preço;
- recalcular relevância por usuário;
- verificar produtos da lista **Quero Comprar**;
- disparar notificações push;
- gerar links de afiliado no clique de saída para a loja.
