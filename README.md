# EA 880

Setup inspirado nos trades do Storm com médias móveis de 8 e 80 (por isso Expert Advisor
880), operando no Éden dos Traders e também inspirado nos setups de Larry Williams 9.1, 9.2
e 9.3 e 123 de Dave Landry. Não necessariamente usando esses setups de forma fiel, apenas
uma inspiração.

## Como o EA opera

- **Decide em vela fechada**, não a cada tick. O sinal lê as barras 1 e 2 (`Sinal()`).
  Desde a v1.16 exige as duas médias **alinhadas e inclinadas** no sentido do trade, e o
  estocástico saiu do sinal.
- **Entra por ordem pendente** — STOP-LIMIT quando o gatilho está além do preço corrente,
  LIMIT quando o preço já passou dele. Ver a medição abaixo: ordem stop pura não funciona.

### A B3 não aceita ordem stop pura (medido)

`tools/DiagnosticoValidade` provou, em 22/08/2026 sobre `WINV26` no Strategy Tester:

| Combinação | Resultado |
|---|---|
| `BUY_STOP` / `SELL_STOP`, DAY **e** GTC, com e sem SL | 8 de 8 rejeitadas, retcode **10022** |
| `BUY_LIMIT` / `SELL_LIMIT`, GTC | rejeitadas — a máscara só tem DAY |
| `BUY_LIMIT` / `SELL_LIMIT`, DAY | 4 de 4 aceitas |
| `BUY_STOP_LIMIT` / `SELL_STOP_LIMIT`, DAY | **8 de 8 aceitas** |

Propriedades medidas: `exec=EXCHANGE`, `SYMBOL_ORDER_MODE=127`,
`SYMBOL_EXPIRATION_MODE=2` (só DAY), `SYMBOL_FILLING_MODE=3` (FOK|IOC), tick 5, point 1,
digits 0, stops level 0, volume mínimo 1.

Duas armadilhas ficam registradas. **`SYMBOL_ORDER_MODE=127` anuncia `STOP` como suportado
e é mentira** — na B3 a ordem stop nativa é stop-limit. E **`TRADE_RETCODE_INVALID_EXPIRATION`
(10022) é um retcode enganoso aqui**: aparece com a validade correta, porque o que o servidor
recusa é o *tipo* de ordem. Não tente resolver mexendo na validade.

O gatilho vai em `price` e o limite resultante em `stoplimit`, colocado
`InpStopLimitTicks` do lado **marketável** (padrão 2 ticks = 10 pontos no WIN). Assim a ordem
preenche no disparo em vez de virar uma limite parada esperando o book voltar — e o custo
dessa garantia aparece no resultado, em vez de o tester prometer um preço que o mercado real
não entrega. Com `InpStopLimitTicks = 0` o limite fica no gatilho e o backtest volta a mentir.
- **Sai por três caminhos**: dois alvos em ordem limite (`ColocaAlvo`), o StopLoss no
  servidor, e o breakeven.
- **Somente conta Netting/Exchange.** O `OnInit` recusa conta em modo Hedging.

### A primeira vela do dia (`InpPermiteBarraAbertura`, padrão não)

A ordem é colocada na vela 1 — a que acabou de fechar — enquanto a vela 0 ainda está em
formação. Com o padrão `false`, um sinal cuja vela 1 seja a **primeira do pregão** é
descartado, e o descarte se comporta como "sem sinal": qualquer pendente antiga também sai.

Duas razões. O range da vela de abertura costuma ser muito maior que o do resto do dia, e é
esse range que define o stop e, por Fibo, o alvo — foi de uma vela dessas que saiu o stop de
905 pontos que cancelou uma entrada por risco. E a vela 2, no momento em que a vela 1 é a de
abertura, ainda é do **dia anterior**: a comparação de máximas e de fechamento contra a média
atravessa o gap noturno e não significa o que a regra pretende.

Detecção pela virada de data entre `rates[1]` e `rates[2]`, em `PrimeiraVelaDoDia()`.

### Onde fica o stop do setup (`precoStop`)

Antes de escolher o modo, vale saber de onde sai o nível. `precoStop` é sempre a extrema da
barra do setup — mínima na compra, máxima na venda — e essa barra é:

- **a vela de entrada** (a que gerou o sinal), no caso normal;
- **a vela mãe**, quando a vela de entrada é um *inside bar* — ou seja, quando a barra
  anterior engloba a de entrada em máxima e mínima (`InsideBar()`). Aí stop e alvo saem da
  mãe, não do inside bar, e o stop fica mais largo.

O stop enviado ao servidor é `precoStop` ∓ 1 tick. **Isso não depende do modo de risco:**
com `riscoMoeda` e `riscoPorCento` ambos em 0 o EA usa `Lote1`/`Lote2` fixos e o stop
continua exatamente aí — na vela de entrada, ou na mãe do inside bar.

### Os dois modos de stop (`InpTipoStop`)

| | `STOP_FANTASMA` (padrão) | `STOP_FIXO` |
|---|---|---|
| SL enviado ao servidor | catástrofe, `stopInicial` pontos além do setup | no próprio preço do setup |
| Dispara com pavio | não — só com **fechamento** de vela além do nível | sim |
| O que acontece ao violar | `ColocaStop()` traz o SL para a extrema da última barra | nada: o stop já disparou |
| Trailing | sim, por essa conversão | **não** — fica parado onde entrou |
| Visível no book | não | sim |
| `stopInicial` | usado | **ignorado** (avisado no log do init) |

O fantasma existe para não ser caçado no book e para um pavio isolado não tirar do trade.
O preço disso está logo abaixo.

### O risco configurado não é o risco real no modo Fantasma

`CalculaLotes()` dimensiona por `|precoEntrada - precoStop|` — a distância do **fantasma**.
Mas no modo Fantasma quem limita a perda é o stop de catástrofe, que está `stopInicial`
pontos mais longe. Com os defaults, num caso real medido em 12/08/2026:

```
entrada → stop fantasma       905 pontos      ← distância do setup
entrada → SL real (servidor)  905 + 2000 = 2905 pontos
perda máxima por contrato     2905 × R$0,20 = R$581
risco configurado (1%)        R$100
```

Ou seja: **o "1% de risco" é, no pior caso, 5,8%.** É estrutural do modo Fantasma e é
anterior à auditoria. `STOP_FIXO` resolve por construção — lá o risco calculado e o risco
real são o mesmo número.

### Os dois campos de risco

São mutuamente exclusivos e o `OnInit` recusa os dois preenchidos:

| Configuração | Efeito |
|---|---|
| `riscoMoeda > 0` | risco fixo nessa quantia da moeda da conta, por trade |
| `riscoPorCento > 0` | risco = saldo × pct/100, **relido a cada entrada** (acompanha o saldo) |
| ambos = 0 | cai para lote fixo: usa `Lote1` e `Lote2` diretamente |

De qualquer um sai um valor em moeda, que vira contratos por
`total = valor / (distância × tickValue/tickSize)` e é dividido entre os dois alvos. Quando
não paga o volume mínimo, **a entrada é cancelada** em vez de arredondada para cima — era
esse arredondamento que fazia a v1.13 abrir 2 contratos onde o risco pedido não cabia em 1.

## Estado atual — auditoria de agosto de 2026

O EA foi revisitado para responder se poderia rodar em conta real. Foram encontrados
**11 bugs P0** (impediam ou ameaçavam a conta real) e **13 P1**. Os quatro mais graves:

1. O envio de ordem era um `do { OrderSend } while(!orderSent)` **infinito**, reenviando a
   cada 100 ms. Ver a anomalia do erro 4756 abaixo.
2. **Nenhum magic number.** `DeletaAlvo()` apagava qualquer ordem limite da conta, de
   qualquer ativo — e rodava a cada tick sem posição. Efeito colateral: toda entrada que
   saía como LIMIT era apagada no tick seguinte e nunca executava.
3. O `OnInit` recusava símbolo com lote mínimo acima de 0.01, ou seja, **se recusava a
   iniciar em WIN/WDO**.
4. `NovaVela()` comparava contagem de barras. `Bars()` não é monotônico: atingido o limite
   de barras do gráfico, entra uma barra e sai outra, a contagem não muda e a vela nova
   nunca é detectada — o EA emudece em silêncio.

### O filtro de pullback está inerte desde a v1.11

Na v1.11 (`d3b042d`, 20/01/2025) a condição do pullback virou:

```cpp
rates[2].high > rates[1].high && ((VelaDeBaixa(1) && rates[1].close > maFast[1]) || (rates[1].close > maFast[1]))
```

`(X && P) || P` reduz a `P`. Logo `VelaDeAlta()`/`VelaDeBaixa()` **nunca surtiram efeito**, e
a exigência `rates[1].open > maFast[1]`, que a v1.10 tinha acabado de introduzir, se perdeu
junto. **Todo backtest da v1.11 em diante testou um sinal mais frouxo do que o autor
pensava.** A v1.14 reescreveu a expressão na forma equivalente comprovada; restaurar o
filtro é decisão de estratégia, ainda em aberto — a v1.16 seguiu outro caminho e passou a
exigir as médias inclinadas, o que produz um conjunto de sinais **estritamente menor** que o
da v1.15 sem estocástico (verificado nas 64 combinações dos predicados).

Segunda observação, ainda em aberto: o ramo do estocástico exige o pullback mas **não** exige
fechamento acima da média rápida. Como o ramo do pullback já cobre esse caso, o estocástico
só acrescenta entradas em que a barra fechou do lado errado da média rápida — contramão do
filtro de tendência. Está desligado por padrão (`usaStoch=false`).

### A anomalia do erro 4756 neste terminal

Neste terminal (XP, build 6116) o `OrderSend` devolve **`false` com `retcode = 0` e erro
4756 mesmo quando a ordem executou na bolsa**. O que salva é que o terminal preenche
`result.order` — ticket atribuído pelo servidor é aceitação.

**Nunca escrever código que trate o retorno booleano do `OrderSend` como veredito neste
ambiente.** É exatamente o que a v1.14 fazia, e combinado com o laço infinito significava
duplicar a ordem a cada 100 ms. O contador `retorno_falso_mas_executou`, no resumo do
`OnDeinit`, mede se isso continua acontecendo.

## Artefatos

| Arquivo | O que é |
|---|---|
| `880.mq5` | v1.18 — correções P0/P1, sinal sem estocástico, dois modos de stop, entrada por stop-limit, filtro da 1ª vela |
| `tools/DiagnosticoValidade.mq5` | EA de diagnóstico: prova que tipo/validade/stop o servidor aceita |
| `legacy/v1.13/880_v113_baseline.mq5` | v1.13 congelada (tag `v1.13-baseline`): **grupo de controle** |
| `legacy/v1.14/880_v114_fidelidade.mq5` | v1.14 — v1.13 com `Sinal()` equivalente e sem o ramo Hedge |

As duas versões em `legacy/` recusam iniciar fora do Strategy Tester: têm todos os bugs P0 e
não podem ser anexadas a um gráfico. Essa guarda é a única diferença delas para o commit de
origem.

## Compilar

Use o MetaEditor **da instalação da XP** — o da XM resolve includes pelo data folder errado:

```bash
"/mnt/c/Program Files/MetaTrader 5 XP/MetaEditor64.exe" \
  /compile:"C:\Users\...\MQL5\Experts\880\880.mq5" \
  /log:"C:\Users\...\MQL5\Experts\880\compile.log"
```

O **exit code mente** (é o número de arquivos) e o log sai em **UTF-16LE**. Leia o log:

```bash
iconv -f UTF-16 -t UTF-8 compile.log | perl -pe 's/\r//'
```

## Encoding

Os fontes são **UTF-8 com CRLF**, que é o que o MetaEditor grava. As versões até a 1.13
estavam em UTF-16LE (herança de um MetaEditor antigo), o que fazia o git tratá-las como
binário e tornava todo diff ilegível. Não voltar para UTF-16.

## Validação

O plano de validação, as divergências esperadas entre versões e o critério de aprovação
estão em [`docs/criterio-aprovacao.md`](docs/criterio-aprovacao.md).
