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

## Encoding e git

- `880.mq5` é **UTF-16LE com BOM e CRLF** — é o que o MetaEditor grava. Editando pelo WSL,
  converter para UTF-8/LF, editar, e converter de volta. Confira o round-trip com `cmp`
  antes de gravar: o arquivo **não termina em nova linha** e `sed` corrompe o último byte.
  Use `perl -pe 's/\n/\r\n/'`, que só toca em `\n` reais.
- O git trata o `.mq5` como binário. O `.gitattributes` declara o driver de diff; habilitar
  uma vez por clone com `git config diff.mql5.textconv "iconv -f UTF-16 -t UTF-8"`.
- Comentários e strings em **português acentuado**. Não misturar com texto sem acento.

## Compilar

Sempre com o MetaEditor da instalação da **XP** (`C:\Program Files\MetaTrader 5 XP`) — o da
XM resolve includes pelo data folder errado. O exit code mente; o log sai em UTF-16LE e é
ele que diz se compilou. Comando completo no [`README.md`](README.md).

## Versões congeladas

`legacy/v1.13/` e `legacy/v1.14/` são grupos de controle e **não devem ser alterados**. Ambos
recusam rodar fora do Strategy Tester, porque têm todos os bugs P0.
