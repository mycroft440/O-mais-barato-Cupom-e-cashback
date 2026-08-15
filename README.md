# O Mais Barato — Cupom e Cashback

Aplicativo Flutter para descobrir ofertas, cupons e oportunidades personalizadas, com lista **Quero Comprar** para acompanhar preços e novos cupons.

## Objetivo

Ser mais eficiente que grupos e canais de cupons no WhatsApp: menos spam, maior relevância individual, comparação de preço final e alertas ligados à intenção real de compra.

## Personalização

O app combina preferências escolhidas pelo usuário com comportamento observado no próprio app. Nesta primeira versão entram:

- Roupas
- Acessórios
- Brinquedos
- Tecnologia
- Suplementos

Pesquisas têm peso baixo; cliques têm peso maior; produtos salvos em **Quero Comprar** têm peso ainda maior. Esses sinais ordenam o feed e ajudam a recomendar itens similares.

## Quero Comprar

O usuário pode salvar um produto por 1, 3, 6 ou 12 meses e definir um preço-alvo opcional. A arquitetura está preparada para disparar alertas quando houver preço menor ou novo cupom aplicável.

## Cupons e ofertas

A interface diferencia cupons verificados de cupons ainda não confirmados. Os dados atuais são demonstrativos; produção deverá usar conectores oficiais/permitidos para marketplaces e programas de afiliados.

## GitHub Actions

O workflow `Android CI` executa:

1. geração do host Android;
2. `flutter pub get`;
3. `flutter analyze`;
4. `flutter test`;
5. `flutter build apk --release`;
6. upload do APK como artifact do workflow.

## Próxima camada de produção

- conectores de marketplaces e afiliados;
- catálogo canônico para identificar o mesmo produto entre lojas;
- histórico de preços;
- validação contínua de cupons;
- notificações push;
- backend para monitoramento 24/7;
- métricas de relevância, validade e economia real.

> Integrações reais com marketplaces e programas de afiliados exigem credenciais próprias e aprovação nos respectivos programas.
