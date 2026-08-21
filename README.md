# O Mais Barato — Cupom e Cashback

Aplicativo Flutter para descobrir ofertas, comparar anúncios equivalentes, encontrar o menor preço, acompanhar produtos desejados e futuramente combinar cupons, cashback e links de afiliado.

## Regra principal da comparação

Para cada produto/modelo, o app deve:

1. buscar produtos relacionados à pesquisa;
2. priorizar os modelos mais populares quando houver dado confiável de popularidade;
3. agrupar apenas anúncios equivalentes do mesmo produto;
4. comparar os preços desses anúncios;
5. exibir somente o anúncio de menor preço de cada produto.

**Não existe desconto mínimo obrigatório.** Se um anúncio custa R$ 95 e o próximo custa R$ 100, o anúncio de R$ 95 continua sendo exibido como o menor preço. O percentual de diferença serve apenas como informação ao usuário.

A referência exibida no cartão usa a mediana dos outros anúncios equivalentes para evitar comparações distorcidas por um vendedor excessivamente caro.

Na busca por uma categoria ampla, como **tênis**, a lista deve representar vários modelos populares. Cada modelo aparece uma única vez e o cartão exibido é sempre o anúncio de menor preço encontrado para aquele modelo.

## Busca real

O backend FastAPI está preparado para usar o catálogo do Mercado Livre como primeira fonte real:

- pesquisa de produtos de catálogo;
- consulta dos anúncios concorrentes vinculados ao mesmo produto;
- escolha automática do menor preço;
- posição entre os mais vendidos quando disponível.

O aplicativo consulta o backend quando `API_BASE_URL` é informado em `--dart-define`. Sem backend configurado, usa dados demonstrativos para desenvolvimento.

## Personalização

O app combina preferências escolhidas pelo usuário com comportamento observado no próprio app. Pesquisas, cliques e produtos monitorados alimentam o ranking personalizado sem alterar a regra principal: cada produto continua representado pelo menor preço encontrado.

## Quero Comprar

O usuário pode salvar um produto por 1, 3, 6 ou 12 meses e definir um preço-alvo opcional. A arquitetura está preparada para alertar quando aparecer um preço ainda menor ou um novo cupom aplicável.

## Cupons, cashback e afiliados

Cupons atuais ainda são demonstrativos. A camada de produção deverá integrar fontes oficiais/permitidas, validar regras e validade, calcular cashback e gerar os links de afiliado no backend, sem expor credenciais no aplicativo Flutter.

## Backend

Para executar localmente:

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export MERCADOLIVRE_ACCESS_TOKEN="seu_token"
uvicorn main:app --reload
```

## Flutter

Para apontar o app para o backend:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Em produção, use HTTPS e uma URL pública do backend.

## GitHub Actions

O workflow `Android CI` executa geração do host Android, `flutter pub get`, análise estática, testes, build do APK release e upload do APK como artifact.

## Próximas camadas

- hospedar o backend 24/7;
- adicionar outras lojas e marketplaces;
- catálogo canônico entre lojas diferentes;
- histórico de preços;
- cupons reais;
- cashback;
- links de afiliado;
- notificações push;
- métricas de relevância e economia real.
