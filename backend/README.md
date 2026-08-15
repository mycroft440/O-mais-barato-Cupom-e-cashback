# Backend 24/7

O monitoramento contínuo de preços e cupons deve rodar fora do telefone.

## Responsabilidades

- receber ofertas dos conectores de marketplaces;
- normalizar o mesmo produto entre lojas;
- validar validade/restrições dos cupons;
- manter histórico de preço;
- recalcular score de oferta e relevância por usuário;
- verificar produtos da lista **Quero Comprar**;
- disparar notificações push somente quando a regra do usuário for satisfeita;
- gerar links de afiliado no clique/saída para a loja.

## Critério para ser melhor que grupos de WhatsApp

O backend deve medir continuamente:

- latência entre encontrar e publicar uma oferta;
- taxa de cupons que ainda funcionam;
- economia real considerando desconto aplicável;
- CTR por recomendação;
- taxa de alertas ignorados;
- conversão por categoria/interesse;
- falso positivo de produto similar.

A meta não é enviar mais notificações; é enviar menos notificações e acertar mais.

## Segurança

Credenciais de APIs e afiliados nunca devem ser colocadas no aplicativo Flutter. Elas pertencem ao backend/secret manager.
