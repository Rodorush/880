# Critério de aprovação e plano de validação — EA 880

Este documento existe para ser preenchido **antes** do primeiro backtest de avaliação. É o
item que separa auditoria de negociação consigo mesmo: sem número escrito antes, todo
resultado vira "quase lá, é só ajustar um parâmetro".

## 1. Teste de fidelidade (não avalia estratégia, valida o método)

Objetivo: provar que a v1.14 é comportamentalmente idêntica à v1.13. Se divergir, o erro
está na refatoração, não na estratégia — e nada do que vier depois é confiável.

| Passo | O quê |
|---|---|
| 1 | Rodar `legacy/v1.13/880_v113_baseline` no Strategy Tester. Anotar `.set`, janela, símbolo, timeframe e modo de modelagem. |
| 2 | Rodar `legacy/v1.14/880_v114_fidelidade` com **exatamente** os mesmos parâmetros. |
| 3 | Comparar os relatórios. **Exigência: idênticos.** |

Lembretes de ambiente:

- A **data final do Strategy Tester é exclusiva**: para operar até 14/08, pedir 15/08.
- As duas versões de `legacy/` só rodam no tester, por guarda no `OnInit`.

## 2. Divergências esperadas da v1.15

Declaradas antes de rodar. **Divergência fora desta lista é bug, não melhoria.**

| Mudança | Efeito esperado no backtest |
|---|---|
| `DeletaAlvo()` deixa de matar entradas LIMIT (agora separadas por magic) | Aparecem trades que a v1.13/v1.14 nunca fizeram |
| Alvos calculados na barra do sinal, não na barra corrente | TPs em preços diferentes quando o preenchimento demora mais de uma vela |
| Normalização de volume e de preço | Lotes e níveis podem mudar |
| `CalculaLotes()` sem o piso artificial de 2 contratos | Tamanhos menores quando o risco pedido é pequeno; entrada cancelada quando o risco não paga o volume mínimo |
| `stopInicial` e `breakEvenGap` convertidos de pontos via `_Point` | **Nenhum** efeito em WIN (point 1); muda tudo em símbolo com digits > 0 |
| `NovaVela()` por tempo de barra | Em geral idêntico no tester; pode diferir no início da série |
| `BateuMeta()` líquido, filtrado por magic e por tipo de deal | Meta bate mais tarde (só com `meta > 0`; o padrão é 0) |
| Meta batida não interrompe mais a gestão de posição aberta | Só muda com `meta > 0` |
| Breakeven passa a rodar em venda sem SL prévio | Irrelevante na prática: a entrada sempre envia SL |
| Ordem pendente sobrevive a troca de timeframe e a recompilação | Nenhum efeito no tester |

## 3. Critério de aprovação — A DEFINIR

> Os quatro números abaixo são decisão do usuário e ainda **não** foram preenchidos.
> Nada de avaliação de edge deve rodar antes disso.

- **Edge líquido mínimo por trade, em ticks:** `[A DEFINIR]`
  Piso defensável é **1 tick** — abaixo da granularidade física do preço não existe
  estratégia, existe ruído. É o default de `InpPisoEdgeTicks`.
- **Fator de lucro líquido mínimo:** `[A DEFINIR]`
- **Drawdown máximo tolerável**, sobre o capital que vai de fato ser usado: `[A DEFINIR]`
- **Janelas out-of-sample consecutivas** em que isso precisa se sustentar: `[A DEFINIR]`
  Um único in-sample não vale nada. Walk-forward é o mínimo, e a profundidade de dado
  disponível define as janelas — levantar essa profundidade é pré-requisito.

**Consequência registrada: reprovou, arquiva.** Arquivar com um número na mão é um
resultado — é a resposta que o autor procurava há anos —, não um fracasso.

O `OnTester()` já implementa o piso: devolve o resultado **líquido** (lucro + comissão +
taxa + swap) e zera a passada quando o edge fica abaixo de `InpPisoEdgeTicks` ou quando há
menos de `InpMinTrades` saídas. Nenhuma métrica bruta deve aparecer em relatório, painel ou
planilha.

## 4. O que o backtest deste EA **não** responde

O sinal é avaliado em vela fechada, então o modo de modelagem não muda quais barras geram
sinal. Mas o resultado por trade não é confiável no tester, e isso não é bug — é estrutural:

- A **entrada** é ordem pendente e as **duas saídas de lucro são ordens limite**.
- O tester preenche uma limite quando o preço **toca** o nível. No book real você entra no
  fim da fila e só é preenchido quando o preço **atravessa** — preferencialmente quando o
  mercado seguiu contra você (seleção adversa).
- Como o lado ganhador do trade é justamente o que o tester superestima, o viés é
  sistematicamente para cima.

Nenhum modo de tick conserta isso: o preenchimento otimista de ordem limite é **modelo do
tester**, não falta de dado. Tick real compraria slippage honesto em ordem **a mercado** — e
`WIN$N` tem 0,00% de ticks com bid/ask, o que exige o símbolo personalizado.

Como quantificar sem adivinhar:

1. Reexecutar o backtest enviando as limites **1 tick pior** (mais difícil de executar).
2. Ou comparar com uma variante que entra e sai **a mercado**.
3. A diferença é o tamanho do risco de execução. Se ela consome o resultado, a estratégia
   depende de posição na fila do book.

## 5. Demo antes de real

Anexar em `XPMT5-DEMO` com `InpPermiteContaReal = false` (é o padrão; o `OnInit` recusa
conta real sem ele) e conferir no journal, ao fim de cada pregão:

1. `Execução: envios=... retorno_falso_mas_executou=N rejeitados=M` no `OnDeinit`.
2. **Uma** aceitação por entrada — nunca duas no mesmo segundo.
3. Nenhum `deal` com volume acima do configurado.
4. Qualquer linha `REJEITADO em definitivo`: dizem qual retcode a corretora devolveu, e é aí
   que aparecem filling mode e nível de stops errados.
