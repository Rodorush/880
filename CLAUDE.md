# EA 880 — regras operacionais

## O que este repositório é

Um único Expert Advisor MQL5, arquivo único, revisitado em agosto de 2026 para auditoria de
corretude antes de conta real. Contexto, achados e artefatos: [`README.md`](README.md).
Critério de aprovação e divergências esperadas: [`docs/criterio-aprovacao.md`](docs/criterio-aprovacao.md).

## Invariantes que não podem regredir

1. **Um único ponto de envio.** Todo `OrderSend` passa por `EnviaRequest()`. Nunca chamar
   `OrderSend` direto, e nunca reenviar em laço sem limite.
2. **O retorno booleano do `OrderSend` não é veredito.** Neste terminal ele devolve `false`
   com erro 4756 mesmo quando a ordem executou; `result.order != 0` é aceitação.
   Sempre classificar `result.retcode`.
3. **Toda leitura de posição, ordem e histórico é filtrada por magic.** `magicEntrada` para
   entrada e posição, `magicAlvo` (= magic + 1) para os alvos. Nunca usar `OrdersTotal()`,
   `PositionsTotal()`, `OrderGetTicket(0)` ou `PositionGetTicket(0)` sem filtrar — são da
   conta inteira e o EA acaba mexendo em ordem manual ou de outro robô.
4. **Netting-only.** O `OnInit` recusa conta em modo Hedging.
5. **Nenhuma métrica bruta.** Resultado é sempre líquido de comissão, taxa e swap — no
   `OnTester()`, no `BateuMeta()` e em qualquer relatório.
6. **Preço e volume normalizados antes de enviar**: preço na grade do tick e nos dígitos do
   símbolo, volume no passo, filling derivado de `SYMBOL_FILLING_MODE`. O EA precisa
   funcionar tanto em WIN/WDO (digits 0, lote inteiro) quanto em CFD.
7. **Estado se reconstrói, não se lembra.** GlobalVariable é cache do que não dá para deduzir
   da posição (a barra do sinal). O `OnInit` recusa iniciar com posição própria e estado
   incompleto, em vez de operar com número inventado.
8. **`StopFantasma()` é gráfico.** Nunca pode bloquear nem repetir: uma tentativa e segue.
9. **Entrada por `ORDER_TYPE_*_STOP_LIMIT`, nunca `ORDER_TYPE_*_STOP`.** O WINV26 rejeita
   a ordem stop pura com retcode 10022 mesmo anunciando suporte em `SYMBOL_ORDER_MODE`.
   O 10022 nesse símbolo quase nunca é a validade — ver [`README.md`](README.md). Antes de
   mudar qualquer coisa em `TipoTempoDoSimbolo()` ou no tipo da ordem, rode
   `tools/DiagnosticoValidade` e decida pelo retcode, não por hipótese.
10. **O dimensionamento mede contra `precoPiorFill`, não contra o gatilho.** No modo
   `STOP_FANTASMA` isso significa que o risco configurado **não** é a perda máxima — ver
   [`README.md`](README.md). Qualquer mudança em `CalculaLotes()` ou em `InpTipoStop` tem de
   respeitar essa distinção, ou o EA volta a mentir sobre o próprio risco.

## Encoding e git

- Os fontes são **UTF-8 com CRLF**, que é o que o MetaEditor grava. Editando pelo WSL,
  preservar o CRLF: use `perl -pe 's/\n/\r\n/'`, que só toca em `\n` reais — `sed 's/$/\r/'`
  corrompe a última linha, porque o arquivo **não termina em nova linha**.
- Versões até a 1.13 estavam em UTF-16LE e o git as tratava como binário. **Não voltar para
  UTF-16**; o `.gitattributes` força diff textual mesmo contra esses blobs antigos.
- Comentários e strings em **português acentuado**. Não misturar com texto sem acento.

## Compilar

Sempre com o MetaEditor da instalação da **XP** (`C:\Program Files\MetaTrader 5 XP`) — o da
XM resolve includes pelo data folder errado. O exit code mente; o log sai em UTF-16LE e é
ele que diz se compilou. Comando completo no [`README.md`](README.md).

## Versões congeladas

`legacy/v1.13/` e `legacy/v1.14/` são grupos de controle e **não devem ser alterados**. Ambos
recusam rodar fora do Strategy Tester, porque têm todos os bugs P0.
