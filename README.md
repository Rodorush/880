# EA 880

Setup inspirado nos trades do Storm com médias móveis de 8 e 80 (por isso Expert Advisor
880), operando no Éden dos Traders e também inspirado nos setups de Larry Williams 9.1, 9.2
e 9.3 e 123 de Dave Landry. Não necessariamente usando esses setups de forma fiel, apenas
uma inspiração.

## Como o EA opera

- **Decide em vela fechada**, não a cada tick. O sinal lê as barras 1 e 2 (`Sinal()`).
- **Entra por ordem pendente** — STOP quando o gatilho está além do preço corrente, LIMIT
  quando o preço já passou dele.
- **Sai por três caminhos**: dois alvos em ordem limite (`ColocaAlvo`), o StopLoss no
  servidor, e o "Stop fantasma" — a linha tracejada no gráfico que, quando violada no
  fechamento de uma vela, faz o EA trazer o SL real para a extrema da última barra
  (`ColocaStop`). Entre uma vela e outra a única proteção é o stop de catástrofe
  (`stopInicial`) enviado junto com a entrada.
- **Somente conta Netting/Exchange.** O `OnInit` recusa conta em modo Hedging.

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
filtro é decisão de estratégia, ainda em aberto.

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
| `880.mq5` | v1.15 — versão de trabalho, com as correções P0 e P1 |
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

## Ler diffs do fonte

`880.mq5` é UTF-16LE e o git o trata como binário. O `.gitattributes` já declara o driver;
habilite-o uma vez por clone:

```bash
git config diff.mql5.textconv "iconv -f UTF-16 -t UTF-8"
```

## Validação

O plano de validação, as divergências esperadas entre versões e o critério de aprovação
estão em [`docs/criterio-aprovacao.md`](docs/criterio-aprovacao.md).
