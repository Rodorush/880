//+------------------------------------------------------------------+
//|                                                 880 (v.1.18).mq5 |
//|                                       Rodolfo Pereira de Andrade |
//|                                    https://rodorush.blogspot.com |
//+------------------------------------------------------------------+
#property copyright "Rodolfo Pereira de Andrade"
#property link      "https://rodorush.blogspot.com"
#property version   "1.18"
#property description "Setup 8/80 no Éden dos Traders. Opera somente em conta Netting."

//--- Estado da estratégia
double lote1, lote2;
double maFast[], maSlow[], stoch[];
double precoEntrada, precoStop, precoTarget;
double precoPiorFill;          //Pior preço de entrada possível, já com o limite do stop-limit
double volumeEntrada;
double tickSize, tickValue, pontoPreco;
double volMin, volMax, volStep;
double stopInit, beGap;
int    digitos, nivelStops;
ENUM_TIMEFRAMES periodo;
int    maHandle_fast, maHandle_slow, stochHandle;
int    sinal;
datetime tempoUltimaVela;
datetime diagUltimaBarra;      //Última barra já reportada pelo diagnóstico

//--- Identificação das ordens do EA
long   magicEntrada, magicAlvo;
ENUM_ORDER_TYPE_FILLING fillingPadrao;
ENUM_ORDER_TYPE_TIME    tipoTempo;

//--- Cache da meta diária
datetime metaDia;
double   metaSaldo;
int      metaDeals;

//--- Diagnóstico de execução (ver README.md, anomalia do erro 4756)
ulong  totalEnvios, retornoFalsoMasExecutou, enviosRejeitados;

MqlRates rates[];
MqlTick  lastTick;

string robot = "880 1.18"; //Nome do EA
string simbolo;
string gv;                 //Prefixo das GlobalVariables deste EA/símbolo
//-----------------------------------------------------
// Parâmetros
//-----------------------------------------------------
//| Onde mora o stop real da posição.
//|
//| FANTASMA: o stop do setup (precoStop) fica só como linha no gráfico; o SL
//|   enviado ao servidor é de catástrofe, 'stopInicial' pontos além. O stop só
//|   vira executável quando uma vela FECHA violando o nível, e aí vai para a
//|   extrema da última barra. Não é caçável no book e um pavio isolado não tira
//|   do trade -- mas a perda máxima é a do stop de catástrofe, não a do setup,
//|   e é isso que o dimensionamento por risco NÃO enxerga. Ver README.md.
//|
//| FIXO: o SL vai ao servidor já no preço do setup. Dispara com pavio, mas a
//|   perda máxima é a que o CalculaLotes() usou para dimensionar. Sem trailing:
//|   o stop fica parado onde entrou. 'stopInicial' é ignorado.
enum ENUM_TIPO_STOP
{
   STOP_FANTASMA,   //Fantasma (SL no servidor só de catástrofe)
   STOP_FIXO        //Fixo (SL no servidor no preço do setup)
};

input group "Parâmetros"
input double meta          = 0;    //Meta diária em moeda. Se 0 não usa
input double breakEvenFibo  = 161.8; // Gatilho para BreakEven em porcentagem de Fibo
input double breakEvenMoeda = 0;     // Gatilho para BreakEven em valor de moeda
input double breakEvenGap  = 5;    //Valor do BreakEven em pontos da entrada real
input ENUM_TIPO_STOP InpTipoStop = STOP_FANTASMA; //Tipo de stop
input double stopInicial   = 2000.0; //Stop de catástrofe em pontos (só no modo Fantasma)
input bool   usaStoch      = false;//Usa Estocástico?

// Risco em moeda tem precedência sobre risco em %; o OnInit recusa os dois
// preenchidos. Com os dois em 0 o lote é fixo e o risco por trade passa a ser
// ditado pelo stop do setup -- 1 tick além da vela de entrada, ou da mãe dela
// quando a vela de entrada é um inside bar. Ver README.md.
input group "Risco por operação"
input double riscoMoeda    = 0;    //Risco em moeda por trade. Se 0, vale o Risco em %
input double riscoPorCento = 1;    //Risco em % do saldo. Ambos 0: lote fixo, risco = stop do setup

input group "Alvos em Fibo (%)"
input double alvoFibo1     = 161.8;//Alvo 1 em porcentagem de Fibo
input double Lote1         = 0.1;  //Lotes do Alvo 1. Só é usado com os dois Riscos em 0
input double alvoFibo2     = 200;  //Alvo 2 em porcentagem de Fibo
input double Lote2         = 0.1;  //Lotes do Alvo 2. Só é usado com os dois Riscos em 0

// -------------------------
// Novos alvos em Moeda
// -------------------------
input group "Alvos em Moeda ( $ / € / ... )"
// Se alvoMoeda1 for 10, por exemplo, significa que o TP do 1º alvo deve realizar 10 da moeda da conta
input double alvoMoeda1 = 0;       //Alvo 1 em moeda da conta. Exige alvoFibo1 = 0
input double alvoMoeda2 = 0;       //Alvo 2 em moeda da conta. Exige alvoFibo2 = 0

//-----------------------------------------------------
// Configurações de Médias Móveis
//-----------------------------------------------------
input group "Fast MA"
input int ma_period_fast                 = 8; 
input int ma_shift_fast                  = 0; 
input ENUM_MA_METHOD ma_method_fast      = MODE_EMA; 
input ENUM_APPLIED_PRICE applied_price_fast = PRICE_CLOSE; 

input group "Slow MA"
input int ma_period_slow                 = 80; 
input int ma_shift_slow                  = 0; 
input ENUM_MA_METHOD ma_method_slow      = MODE_EMA; 
input ENUM_APPLIED_PRICE applied_price_slow = PRICE_CLOSE; 

//-----------------------------------------------------
// Configurações de Estocástico
//-----------------------------------------------------
input group "Estocástico Lento"
input int Kperiod                        = 14; 
input int Dperiod                        = 3; 
input int slowing                        = 3; 
input ENUM_MA_METHOD ma_method           = MODE_SMA; 
input ENUM_STO_PRICE price_field         = STO_LOWHIGH; 

input group "Níveis Estocástico"
input int sc = 80; //Sobrecompra
input int sv = 20; //Sobrevenda

//-----------------------------------------------------
// Horário de funcionamento
//-----------------------------------------------------
input group "Horário de Funcionamento"
input int  startHour     = 9;    //Hora de início dos trades
sinput int startMinutes  = 0;    //Minutos de início (fora da otimização)
input int  stopHour      = 17;   //Hora de interrupção
sinput int stopMinutes   = 45;   //Minutos de interrupção (fora da otimização)
input bool InpPermiteBarraAbertura = false; //Permitir ordem na 1a vela do dia?


//-----------------------------------------------------
// Execução e segurança
//-----------------------------------------------------
input group "Execução e segurança"
sinput long InpMagic            = 880;   //Magic number (alvos usam Magic+1)
sinput bool InpPermiteContaReal = false; //Permitir rodar em conta REAL
sinput int  InpMaxTentativas    = 3;     //Tentativas em erro transitório
sinput int  InpDesvioPontos     = 10;    //Desvio máximo (pontos) ao fechar a mercado
sinput int  InpStopLimitTicks   = 2;     //Ticks marketáveis no disparo (0 = limite no gatilho)
sinput bool InpDiagSinal        = false; //Diagnóstico: 1 linha por vela avaliada

//-----------------------------------------------------
// Critério de otimização (OnTester)
//-----------------------------------------------------
input group "Critério de otimização"
sinput int    InpMinTrades      = 30;    //Mínimo de saídas para a passada valer
sinput double InpPisoEdgeTicks  = 1.0;   //Piso de edge líquido, em ticks por contrato

//+------------------------------------------------------------------+
//| Infraestrutura: normalização, permissões e envio de ordens       |
//+------------------------------------------------------------------+

//| Arredonda um preço para o tick do símbolo e para os dígitos dele.
//| Preço fora da grade de tick é motivo clássico de rejeição (10015).
double NormalizaPreco(double preco)
{
   if(tickSize > 0) preco = MathRound(preco/tickSize)*tickSize;
   return(NormalizeDouble(preco,digitos));
}

//| Trunca o volume para o passo do símbolo, sempre para BAIXO, para
//| nunca arriscar mais do que o pedido. Não força o mínimo: quem chama
//| decide o que fazer quando o resultado fica abaixo de volMin.
double NormalizaVolume(double volume)
{
   if(volStep > 0) volume = MathFloor(volume/volStep + 1e-8)*volStep;
   if(volume > volMax) volume = volMax;
   return(NormalizeDouble(volume,2));
}

//| Afasta o stop da referência até o mínimo exigido pelo servidor.
//| Em WIN o nivelStops é 0 e nada muda; em CFD costuma ser > 0.
//|
//| @param referencia  preço da ordem pendente, ou bid/ask para posição aberta
double RespeitaNivelStops(double stop, double referencia, bool paraCompra)
{
   if(nivelStops <= 0) return(NormalizaPreco(stop));
   double minimo = nivelStops*pontoPreco;
   if(paraCompra  && referencia - stop < minimo) stop = referencia - minimo;
   if(!paraCompra && stop - referencia < minimo) stop = referencia + minimo;
   return(NormalizaPreco(stop));
}

//| Retorna false e diz qual camada bloqueou. Sem isso o EA fica
//| reenviando ordem contra um terminal que nunca vai aceitar.
bool NegociacaoPermitida()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   { Print("Bloqueado: AutoTrading desligado no terminal."); return(false); }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   { Print("Bloqueado: negociação não permitida para este EA."); return(false); }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   { Print("Bloqueado: negociação não permitida para esta conta."); return(false); }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   { Print("Bloqueado: a conta não permite negociação por Expert Advisor."); return(false); }
   return(true);
}

//| Deriva o modo de preenchimento do próprio símbolo. Fixar RETURN, como
//| fazia até a v1.14, é rejeitado pelo WIN (que só aceita FOK|IOC).
ENUM_ORDER_TYPE_FILLING FillingDoSimbolo()
{
   int modos = (int)SymbolInfoInteger(simbolo,SYMBOL_FILLING_MODE);
   if((modos & SYMBOL_FILLING_FOK) != 0) return(ORDER_FILLING_FOK);
   if((modos & SYMBOL_FILLING_IOC) != 0) return(ORDER_FILLING_IOC);
   return(ORDER_FILLING_RETURN);
}

//| Escolhe a validade da ordem pendente.
//|
//| Medido em WINV26 (22/08/2026, tools/DiagnosticoValidade): a máscara
//| SYMBOL_EXPIRATION_MODE vale 2, ou seja SÓ DAY -- GTC volta como
//| TRADE_RETCODE_INVALID_EXPIRATION (10022). Em execução por bolsa a pendente
//| é sempre ordem do dia.
//|
//| CUIDADO: 10022 nesse símbolo também aparece em ordem STOP com a validade
//| correta. Ali o problema é o TIPO de ordem, não a validade -- não tente
//| consertar mexendo aqui. Ver README.md.
ENUM_ORDER_TYPE_TIME TipoTempoDoSimbolo()
{
   long exec = SymbolInfoInteger(simbolo,SYMBOL_TRADE_EXEMODE);
   if(exec == SYMBOL_TRADE_EXECUTION_EXCHANGE) return(ORDER_TIME_DAY);

   int modos = (int)SymbolInfoInteger(simbolo,SYMBOL_EXPIRATION_MODE);
   if((modos & SYMBOL_EXPIRATION_GTC) != 0) return(ORDER_TIME_GTC);
   if((modos & SYMBOL_EXPIRATION_DAY) != 0) return(ORDER_TIME_DAY);
   return(ORDER_TIME_GTC);
}

//| Só estes retcodes valem nova tentativa. Qualquer outro é definitivo e
//| reenviar significa martelar o servidor com uma ordem que ele já recusou.
bool RetcodeTransitorio(uint rc)
{
   switch(rc)
   {
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_TIMEOUT:
      case TRADE_RETCODE_CONNECTION:
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
      case TRADE_RETCODE_ORDER_CHANGED:
      case TRADE_RETCODE_LOCKED:
      case TRADE_RETCODE_FROZEN:
         return(true);
   }
   return(false);
}

//| Único ponto de envio do EA. Substitui os do{...}while(!orderSent) da
//| v1.14, que reenviavam a cada 100 ms para sempre.
//|
//| @param oque  rótulo da operação, usado no log do Journal
bool EnviaRequest(MqlTradeRequest &req, MqlTradeResult &res, string oque)
{
   if(!NegociacaoPermitida()) return(false);

   req.magic   = (req.magic == 0) ? magicEntrada : req.magic;
   req.symbol  = simbolo;
   req.comment = robot;

   for(int tentativa = 1; tentativa <= InpMaxTentativas; tentativa++)
   {
      ZeroMemory(res);
      ResetLastError();
      totalEnvios++;
      bool ok  = OrderSend(req,res);
      int  err = GetLastError();

      // Anomalia medida neste terminal (build 6116): OrderSend devolve false
      // com retcode 0 e erro 4756 mesmo quando o servidor aceitou a ordem.
      // Ticket atribuído pelo servidor é aceitação - nunca tratar o retorno
      // booleano como veredito aqui. Ver README.md.
      if(!ok && res.order != 0)
      {
         retornoFalsoMasExecutou++;
         Print(oque," : retorno falso (err=",err," retcode=",res.retcode,
               ") mas o servidor devolveu ticket ",res.order," - aceito.");
         return(true);
      }

      if(ok && (res.retcode == TRADE_RETCODE_DONE ||
                res.retcode == TRADE_RETCODE_PLACED ||
                res.retcode == TRADE_RETCODE_DONE_PARTIAL))
         return(true);

      // Sem retcode do servidor a requisição morreu localmente. Reenviar
      // às cegas é justamente o que poderia duplicar posição: não reenvia.
      if(res.retcode == 0 || !RetcodeTransitorio(res.retcode))
      {
         enviosRejeitados++;
         Print(oque," REJEITADO em definitivo. retcode=",res.retcode,
               " err=",err," (",res.comment,"). Não será reenviado.");
         return(false);
      }

      Print(oque," falhou (tentativa ",tentativa,"/",InpMaxTentativas,
            "): retcode=",res.retcode," err=",err);
      Sleep(200);
      SymbolInfoTick(simbolo,lastTick);
   }
   enviosRejeitados++;
   Print(oque," : esgotadas as ",InpMaxTentativas," tentativas. Desistindo.");
   return(false);
}

//| Seleciona a posição do símbolo SE ela for deste EA. Sem o filtro de
//| magic o EA mexe em posição manual ou de outro robô.
bool MinhaPosicao()
{
   if(!PositionSelect(simbolo)) return(false);
   return(PositionGetInteger(POSITION_MAGIC) == magicEntrada);
}

//| Conta as minhas ordens pendentes do símbolo, por magic.
//| @param magicAlvoBusca  magicEntrada para a ordem de entrada, magicAlvo para os alvos
int MinhasOrdens(long magicAlvoBusca)
{
   int achadas = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != simbolo) continue;
      if(OrderGetInteger(ORDER_MAGIC) != magicAlvoBusca) continue;
      achadas++;
   }
   return(achadas);
}

//| Remove as minhas ordens pendentes de um dado magic.
void RemoveOrdens(long magicAlvoBusca, string oque)
{
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != simbolo) continue;
      if(OrderGetInteger(ORDER_MAGIC) != magicAlvoBusca) continue;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ticket;
      req.magic  = magicAlvoBusca;
      EnviaRequest(req,res,oque+" (ticket "+(string)ticket+")");
   }
}

//| Copia barras e buffers conferindo o retorno. CopyRates/CopyBuffer podem
//| devolver menos do que o pedido sem erro; indexar às cegas estoura
//| "array out of range" e mata o EA - tipicamente no attach, com o handle
//| de indicador ainda aquecendo.
bool DadosProntos()
{
   if(CopyRates(simbolo,periodo,0,3,rates) < 3)   return(false);
   if(CopyBuffer(maHandle_fast,0,0,3,maFast) < 3) return(false);
   if(CopyBuffer(maHandle_slow,0,0,3,maSlow) < 3) return(false);
   if(usaStoch && CopyBuffer(stochHandle,0,0,3,stoch) < 3) return(false);
   return(true);
}

//| Grava o estado da operação corrente. GlobalVariable é cache: a fonte da
//| verdade é a posição/ordem no servidor, mas sem isto não dá para
//| reconstruir a barra do sinal depois de reiniciar o terminal.
void SalvaEstado()
{
   GlobalVariableSet(gv+"precoEntrada", precoEntrada);
   GlobalVariableSet(gv+"precoStop",    precoStop);
   GlobalVariableSet(gv+"precoTarget",  precoTarget);
   GlobalVariableSet(gv+"lote1",        lote1);
   GlobalVariableSet(gv+"lote2",        lote2);
   GlobalVariableSet(gv+"volumeEntrada",volumeEntrada);
}

void LimpaEstado()
{
   precoEntrada = 0; precoStop = 0; precoTarget = 0; precoPiorFill = 0;
   lote1 = 0; lote2 = 0; volumeEntrada = 0;
   SalvaEstado();
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   simbolo      = ChartSymbol(0);
   periodo      = ChartPeriod(0);
   gv           = "880_"+simbolo+"_";
   magicEntrada = InpMagic;
   magicAlvo    = InpMagic + 1;

   // --- Tipo de conta -------------------------------------------------
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("EA 880 opera somente em conta Netting/Exchange. ",
            "Esta conta está em modo Hedging - inicialização recusada.");
      return(INIT_FAILED);
   }
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpPermiteContaReal)
   {
      Print("Conta REAL detectada com InpPermiteContaReal=false. ",
            "Inicialização recusada por segurança.");
      return(INIT_FAILED);
   }

   // --- Validação de parâmetros ---------------------------------------
   // INIT_PARAMETERS_INCORRECT poda a combinação na otimização, em vez de
   // gastar uma passada inteira com ela.
   if((alvoFibo1 > 0 && alvoMoeda1 > 0) || (alvoFibo2 > 0 && alvoMoeda2 > 0))
   {
      Print("Alvo em Fibo e Alvo em Moeda não podem ser definidos ao mesmo tempo.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(riscoMoeda > 0 && riscoPorCento > 0)
   {
      Print("Risco em moeda e risco em % não podem ser definidos ao mesmo tempo. ",
            "Zere um deles.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(breakEvenFibo > 0 && breakEvenMoeda > 0)
   {
      Print("BreakEven em Fibo e em Moeda não podem ser definidos ao mesmo tempo.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(startHour   < 0 || startHour   > 23 || stopHour    < 0 || stopHour    > 23 ||
      startMinutes< 0 || startMinutes> 59 || stopMinutes < 0 || stopMinutes > 59)
   {
      Print("Horário de funcionamento fora da faixa válida.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpMaxTentativas < 1)
   {
      Print("InpMaxTentativas precisa ser pelo menos 1.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpStopLimitTicks < 0)
   {
      Print("InpStopLimitTicks não pode ser negativo.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // --- Dados do símbolo ----------------------------------------------
   tickSize   = SymbolInfoDouble(simbolo,SYMBOL_TRADE_TICK_SIZE);
   tickValue  = SymbolInfoDouble(simbolo,SYMBOL_TRADE_TICK_VALUE);
   pontoPreco = SymbolInfoDouble(simbolo,SYMBOL_POINT);
   digitos    = (int)SymbolInfoInteger(simbolo,SYMBOL_DIGITS);
   nivelStops = (int)SymbolInfoInteger(simbolo,SYMBOL_TRADE_STOPS_LEVEL);
   volMin     = SymbolInfoDouble(simbolo,SYMBOL_VOLUME_MIN);
   volMax     = SymbolInfoDouble(simbolo,SYMBOL_VOLUME_MAX);
   volStep    = SymbolInfoDouble(simbolo,SYMBOL_VOLUME_STEP);

   if(tickSize <= 0 || tickValue <= 0 || pontoPreco <= 0 || volStep <= 0 || volMin <= 0)
   {
      Print("Não foi possível ler os dados de negociação de ",simbolo,". Encerrando.");
      return(INIT_FAILED);
   }

   // Inputs documentados "em pontos" viram distância de preço aqui. Até a
   // v1.14 eram somados crus ao preço, o que só batia em símbolo de digits 0
   // (WIN) e errava por ordens de grandeza em qualquer outro.
   stopInit = stopInicial*pontoPreco;
   if(InpTipoStop == STOP_FIXO && stopInicial > 0)
      Print("AVISO: modo de stop FIXO -- 'stopInicial' (",stopInicial,
            " pontos) é ignorado. O SL vai ao servidor no preço do setup.");
   beGap    = breakEvenGap*pontoPreco;

   fillingPadrao = FillingDoSimbolo();
   tipoTempo     = TipoTempoDoSimbolo();

   // --- Indicadores ----------------------------------------------------
   ArraySetAsSeries(maFast,true);
   ArraySetAsSeries(maSlow,true);
   ArraySetAsSeries(stoch,true);
   ArraySetAsSeries(rates,true);

   maHandle_fast = iMA(simbolo,periodo,ma_period_fast,ma_shift_fast,ma_method_fast,applied_price_fast);
   maHandle_slow = iMA(simbolo,periodo,ma_period_slow,ma_shift_slow,ma_method_slow,applied_price_slow);
   stochHandle   = iStochastic(simbolo,periodo,Kperiod,Dperiod,slowing,ma_method,price_field);
   if(maHandle_fast == INVALID_HANDLE || maHandle_slow == INVALID_HANDLE ||
      (usaStoch && stochHandle == INVALID_HANDLE))
   {
      Print("Falha ao criar handle de indicador. Erro = ",GetLastError());
      return(INIT_FAILED);
   }

   // --- Estado ----------------------------------------------------------
   SymbolInfoTick(simbolo,lastTick);
   tempoUltimaVela = 0;
   metaDia = 0; metaSaldo = 0; metaDeals = -1;
   totalEnvios = 0; retornoFalsoMasExecutou = 0; enviosRejeitados = 0;

   if(MinhaPosicao())
   {
      // Estado se reconstrói, não se lembra: a posição é a fonte, a
      // GlobalVariable guarda só o que não dá para deduzir dela (a barra
      // do sinal). Sem esses valores não há como recolocar alvo nem
      // calcular breakeven em Fibo, então é melhor recusar do que operar
      // com número inventado.
      precoEntrada  = GlobalVariableGet(gv+"precoEntrada");
      precoStop     = GlobalVariableGet(gv+"precoStop");
      precoTarget   = GlobalVariableGet(gv+"precoTarget");
      lote1         = GlobalVariableGet(gv+"lote1");
      lote2         = GlobalVariableGet(gv+"lote2");
      volumeEntrada = GlobalVariableGet(gv+"volumeEntrada");

      if(precoEntrada <= 0 || precoStop <= 0 || precoTarget <= 0 || volumeEntrada <= 0)
      {
         Print("Existe posição deste EA (magic ",magicEntrada,") mas o estado salvo ",
               "está incompleto (entrada=",precoEntrada," stop=",precoStop,
               " alvo=",precoTarget," volume=",volumeEntrada,"). ",
               "Feche a posição manualmente ou restaure as GlobalVariables ",
               gv,"* antes de reanexar. Inicialização recusada.");
         return(INIT_FAILED);
      }
      if(InpTipoStop == STOP_FANTASMA)
         StopFantasma((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                      ? precoStop - tickSize : precoStop + tickSize);
      Print("Estado reconstruído: entrada=",precoEntrada," stop=",precoStop,
            " alvo=",precoTarget," volume=",volumeEntrada);
   }
   else
      LimpaEstado();

   Print("880 v1.15 iniciado | ",simbolo," ",EnumToString(periodo),
         " | magic ",magicEntrada,"/",magicAlvo,
         " | exec ",EnumToString((ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(simbolo,SYMBOL_TRADE_EXEMODE)),
         " | filling ",EnumToString(fillingPadrao),
         " (mascara ",(int)SymbolInfoInteger(simbolo,SYMBOL_FILLING_MODE),")",
         " | expiração ",EnumToString(tipoTempo),
         " (mascara ",(int)SymbolInfoInteger(simbolo,SYMBOL_EXPIRATION_MODE),")",
         " | tick ",tickSize," point ",pontoPreco," digits ",digitos,
         " | volume min/passo/max ",volMin,"/",volStep,"/",volMax,
         " | stops level ",nivelStops);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!SymbolInfoTick(simbolo,lastTick)) return;

   if(!DadosProntos())
   {
      // Uma linha por barra, não por tick: aqui é onde o EA fica cego quando
      // o histórico ou o handle do indicador ainda não aqueceram.
      if(InpDiagSinal)
      {
         datetime tb = iTime(simbolo,periodo,0);
         if(tb != diagUltimaBarra)
         {
            diagUltimaBarra = tb;
            PrintFormat("DIAG %s | DADOS NAO PRONTOS | barras=%d maFast=%d maSlow=%d",
                        TimeToString(tb,TIME_DATE|TIME_MINUTES),
                        Bars(simbolo,periodo),
                        BarsCalculated(maHandle_fast),
                        BarsCalculated(maHandle_slow));
         }
      }
      return;
   }

   // --- Janela de funcionamento ---------------------------------------
   if(!TimeSession(startHour,startMinutes,stopHour,stopMinutes,TimeCurrent()))
   {
      if(MinhasOrdens(magicEntrada) > 0)
         RemoveOrdens(magicEntrada,"Entrada (fora do horário)");
      FechaPosicao();
      if(MinhasOrdens(magicAlvo) > 0)
         RemoveOrdens(magicAlvo,"Alvo (fora do horário)");
      Comment("Fora do horário de trabalho. EA dormindo...");
      return;
   }
   Comment("");

   // Meta batida impede entrada nova, mas não abandona posição aberta
   bool metaBatida = BateuMeta();

   // --- A cada nova vela ------------------------------------------------
   if(NovaVela())
   {
      if(InpDiagSinal)
         PrintFormat("DIAG %s | vela nova | barras=%d posicao=%d ordemEntrada=%d"
                     " ordensAlvo=%d metaBatida=%d",
                     TimeToString(rates[1].time,TIME_DATE|TIME_MINUTES),
                     Bars(simbolo,periodo), (int)MinhaPosicao(),
                     MinhasOrdens(magicEntrada), MinhasOrdens(magicAlvo),
                     (int)metaBatida);

      if(MinhaPosicao())
      {
         // Só o modo Fantasma converte o stop em executável aqui. No modo Fixo
         // o SL já está no preço do setup: um fechamento além dele significa
         // que o stop já disparou, e não há trailing -- fica parado onde entrou.
         if(InpTipoStop == STOP_FANTASMA)
         {
            long tipo = PositionGetInteger(POSITION_TYPE);
            if((tipo == POSITION_TYPE_BUY  && rates[1].close < precoStop) ||
               (tipo == POSITION_TYPE_SELL && rates[1].close > precoStop))
               ColocaStop();
         }
      }
      else if(metaBatida)
      {
         if(MinhasOrdens(magicEntrada) > 0)
            RemoveOrdens(magicEntrada,"Entrada (meta batida)");
      }
      else if(Sinal())
      {
         // A ordem sai na vela 1 com a vela 0 ainda em formação. Se a vela 1
         // for a que abriu o pregão, o filtro descarta o sinal - e o descarte
         // se comporta como "sem sinal", inclusive removendo pendente antiga.
         if(!InpPermiteBarraAbertura && PrimeiraVelaDoDia())
         {
            if(InpDiagSinal)
               PrintFormat("DIAG %s | sinal=%d DESCARTADO: vela 1 é a primeira do dia",
                           TimeToString(rates[1].time,TIME_DATE|TIME_MINUTES), sinal);
            if(MinhasOrdens(magicEntrada) > 0)
               RemoveOrdens(magicEntrada,"Entrada (1a vela do dia)");
         }
         else
            ColocaOrdem();
      }
      else if(MinhasOrdens(magicEntrada) > 0)
         RemoveOrdens(magicEntrada,"Entrada (sem sinal nesta vela)");
   }

   // --- Gestão da posição -----------------------------------------------
   if(MinhaPosicao())
   {
      Breakeven();
      // Alvos entram uma vez só, logo após o preenchimento, com a posição
      // ainda inteira. Comparação por tolerância: volume é double.
      if(MinhasOrdens(magicAlvo) == 0 && volumeEntrada > 0 &&
         MathAbs(PositionGetDouble(POSITION_VOLUME) - volumeEntrada) < volStep/2.0)
         ColocaAlvo();
   }
   else
   {
      if(MinhasOrdens(magicAlvo) > 0)
         RemoveOrdens(magicAlvo,"Alvo órfão (sem posição)");
      // O estado NÃO é apagado aqui de propósito. A ordem de entrada pode
      // levar alguns ticks para aparecer em OrdersTotal() depois de aceita,
      // e apagar precoEntrada/precoStop nessa janela deixaria a entrada
      // pendente órfã de stop e de alvo. Estado obsoleto com o EA fora de
      // posição é inofensivo: ColocaOrdem() sempre reescreve antes de
      // enviar, e OnInit limpa quando sobe sem posição.
   }
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   // Só cancela a entrada pendente quando o EA sai de vez. Trocar timeframe,
   // recompilar ou mudar parâmetro recarrega o EA e não pode matar a ordem.
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE || reason == REASON_ACCOUNT)
      RemoveOrdens(magicEntrada,"Entrada (OnDeinit)");

   ObjectDelete(0,"StopFantasma");
   if(maHandle_fast != INVALID_HANDLE) IndicatorRelease(maHandle_fast);
   if(maHandle_slow != INVALID_HANDLE) IndicatorRelease(maHandle_slow);
   if(stochHandle   != INVALID_HANDLE) IndicatorRelease(stochHandle);

   SalvaEstado();
   Print("Execução: envios=",totalEnvios,
         " retorno_falso_mas_executou=",retornoFalsoMasExecutou,
         " rejeitados=",enviosRejeitados);
}

//+------------------------------------------------------------------+
//| Sinal e leitura de barras                                        |
//+------------------------------------------------------------------+

//| Avalia o setup na vela já fechada. Grava o lado em 'sinal' (2 compra,
//| -2 venda, 0 nenhum) e devolve se houve sinal.
bool Sinal()
{
   sinal = 0;

   // Componentes do sinal, sempre lidos na vela já fechada (índices 1 e 2).
   //
   // A v1.16 tirou o estocástico do sinal e passou a exigir as duas médias
   // INCLINADAS, não apenas ordenadas. O conjunto de sinais resultante é um
   // subconjunto estrito do da v1.15 sem estocástico: não abre caso novo.
   bool alinhadoSubindo   = maFast[1] > maSlow[1] && maFast[1] > maFast[2] && maSlow[1] > maSlow[2]; // Médias alinhadas e inclinadas para cima
   bool alinhadoCaindo    = maFast[1] < maSlow[1] && maFast[1] < maFast[2] && maSlow[1] < maSlow[2]; // Médias alinhadas e inclinadas para baixo
   bool cruzouAcima       = rates[2].close < maFast[2] && rates[1].close > maFast[1];                // Cruzou para cima da média rápida
   bool cruzouAbaixo      = rates[2].close > maFast[2] && rates[1].close < maFast[1];                // Cruzou para baixo da média rápida
   bool acimaETopoMenor   = rates[1].close > maFast[1] && rates[2].high > rates[1].high;             // Máxima menor e acima da média rápida
   bool abaixoEFundoMaior = rates[1].close < maFast[1] && rates[2].low < rates[1].low;               // Mínima maior e abaixo da média rápida

   // Compra
   if(alinhadoSubindo)
   {
      if(cruzouAcima || acimaETopoMenor)
      {
         sinal = 2;
      }
   }
   // Venda
   else if(alinhadoCaindo)
   {
      if(cruzouAbaixo || abaixoEFundoMaior)
      {
         sinal = -2;
      }
   }
   // Uma linha por vela avaliada, dizendo exatamente o que o EA viu. Raciocinar
   // sobre por que um sinal não saiu custa mais caro do que medir.
   if(InpDiagSinal)
      PrintFormat("DIAG %s | O=%s H=%s L=%s C=%s | maFast %s->%s | maSlow %s->%s"
                  " | subindo=%d caindo=%d cruzAcima=%d acimaTopoMenor=%d"
                  " cruzAbaixo=%d abaixoFundoMaior=%d | sinal=%d",
                  TimeToString(rates[1].time,TIME_DATE|TIME_MINUTES),
                  DoubleToString(rates[1].open,digitos),
                  DoubleToString(rates[1].high,digitos),
                  DoubleToString(rates[1].low,digitos),
                  DoubleToString(rates[1].close,digitos),
                  DoubleToString(maFast[2],digitos), DoubleToString(maFast[1],digitos),
                  DoubleToString(maSlow[2],digitos), DoubleToString(maSlow[1],digitos),
                  (int)alinhadoSubindo, (int)alinhadoCaindo,
                  (int)cruzouAcima, (int)acimaETopoMenor,
                  (int)cruzouAbaixo, (int)abaixoEFundoMaior, sinal);

   return(sinal != 0);
}

//| Devolve o índice da barra que define stop e alvo.
//|
//| Normalmente é a 1 -- a vela de entrada, aquela que gerou o sinal. Quando a
//| vela 2 engloba a 1, a 1 é um inside bar e quem manda é a MÃE (a vela 2):
//| stop e alvo saem dela, não do inside bar. É a única situação em que o stop
//| não fica na vela de entrada.
//| A vela 1 é a primeira do pregão? Detecta pela virada de data entre as duas
//| velas lidas. Vale a pena barrar porque ali o range costuma ser muito maior
//| que o do resto do dia -- e é o range dela que define o stop e, por Fibo, o
//| alvo -- e porque rates[2] ainda é do dia anterior, do outro lado do gap.
bool PrimeiraVelaDoDia()
{
   MqlDateTime d1, d2;
   TimeToStruct(rates[1].time, d1);
   TimeToStruct(rates[2].time, d2);
   return(d1.day != d2.day || d1.mon != d2.mon || d1.year != d2.year);
}

int InsideBar()
{
   if(rates[2].high > rates[1].high && rates[2].low < rates[1].low)
      return(2);
   return(1);
}

//+------------------------------------------------------------------+
//| Entrada                                                          |
//+------------------------------------------------------------------+
void ColocaOrdem()
{
   int inside = InsideBar();
   if(MinhasOrdens(magicEntrada) > 0)
      RemoveOrdens(magicEntrada,"Entrada anterior");

   precoEntrada = NormalizaPreco((sinal == 2) ? rates[1].high        : rates[1].low);
   precoStop    = NormalizaPreco((sinal == 2) ? rates[inside].low    : rates[inside].high);
   precoTarget  = NormalizaPreco((sinal == 2) ? rates[inside].high   : rates[inside].low);

   // Gatilho da entrada e tipo da ordem.
   //
   // Medido em WINV26 (22/08/2026, tools/DiagnosticoValidade): o símbolo
   // ANUNCIA suporte a ordem stop (SYMBOL_ORDER_MODE=127) mas rejeita
   // ORDER_TYPE_*_STOP com retcode 10022, em qualquer validade. Na B3 a ordem
   // stop nativa é stop-limit; ORDER_TYPE_*_STOP_LIMIT passa. O retcode 10022
   // ali é enganoso: o que o servidor recusa é o TIPO, não a validade.
   double gatilho = NormalizaPreco((sinal == 2) ? precoEntrada + tickSize
                                                : precoEntrada - tickSize);
   ENUM_ORDER_TYPE tipoOrdem =
      (sinal == 2) ? ((gatilho >= lastTick.ask) ? ORDER_TYPE_BUY_STOP_LIMIT
                                                : ORDER_TYPE_BUY_LIMIT)
                   : ((gatilho <= lastTick.bid) ? ORDER_TYPE_SELL_STOP_LIMIT
                                                : ORDER_TYPE_SELL_LIMIT);
   bool ehStopLimit = (tipoOrdem == ORDER_TYPE_BUY_STOP_LIMIT ||
                       tipoOrdem == ORDER_TYPE_SELL_STOP_LIMIT);

   // No disparo, o limite nasce do lado marketável para preencher na hora; o
   // preço dessa garantia é InpStopLimitTicks de escorregamento, e é ele o
   // PIOR preenchimento possível. O risco é medido contra ele, não contra o
   // gatilho, senão o dimensionamento subestima a perda.
   double limite = gatilho;
   if(ehStopLimit && InpStopLimitTicks > 0)
      limite = NormalizaPreco((sinal == 2)
                              ? gatilho + InpStopLimitTicks*tickSize
                              : gatilho - InpStopLimitTicks*tickSize);
   precoPiorFill = limite;

   if(!CalculaLotes()) return;

   volumeEntrada = NormalizaVolume(lote1 + lote2);
   if(volumeEntrada < volMin)
   {
      Print("Volume de entrada (",volumeEntrada,") abaixo do mínimo do símbolo (",
            volMin,"). Entrada cancelada.");
      LimpaEstado();
      return;
   }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action       = TRADE_ACTION_PENDING;
   req.magic        = magicEntrada;
   req.volume       = volumeEntrada;
   req.type_filling = fillingPadrao;
   req.type_time    = tipoTempo;
   req.price        = gatilho;
   req.type         = tipoOrdem;
   if(ehStopLimit) req.stoplimit = limite;
   // No modo Fantasma o SL do servidor é só de catástrofe e o stop do setup
   // fica como linha; no modo Fixo o SL vai direto no preço do setup.
   double afastamento = (InpTipoStop == STOP_FIXO) ? tickSize : stopInit;
   req.sl           = RespeitaNivelStops((sinal == 2) ? precoStop - afastamento
                                                      : precoStop + afastamento,
                                         req.price, (sinal == 2));
   if(InpTipoStop == STOP_FANTASMA)
      StopFantasma((sinal == 2) ? precoStop - tickSize : precoStop + tickSize);

   if(InpDiagSinal)
      PrintFormat("DIAG ordem | sinal=%d tipo=%s preco=%s sl=%s volume=%s"
                  " stoplimit=%s (ask=%s bid=%s)",
                  sinal, EnumToString((ENUM_ORDER_TYPE)req.type),
                  DoubleToString(req.price,digitos), DoubleToString(req.sl,digitos),
                  DoubleToString(req.volume,2),
                  DoubleToString(req.stoplimit,digitos),
                  DoubleToString(lastTick.ask,digitos),
                  DoubleToString(lastTick.bid,digitos));

   if(EnviaRequest(req,res,"Ordem de entrada"))
      SalvaEstado();
   else
   {
      LimpaEstado();
      ObjectDelete(0,"StopFantasma");
   }
}

//+------------------------------------------------------------------+
//| Alvos (ordens limite contra a posição)                           |
//+------------------------------------------------------------------+
void ColocaAlvo()
{
   bool   isBuy      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);

   // Amplitude da barra que gerou o sinal, congelada na entrada. Até a v1.14
   // isto era recalculado de rates[] com a posição já aberta - possivelmente
   // várias barras depois do sinal, portanto na barra errada.
   double amplitude = MathAbs(precoTarget - precoStop);

   for(int n = 1; n <= 2; n++)
   {
      double loteN  = (n == 1) ? lote1      : lote2;
      double fiboN  = (n == 1) ? alvoFibo1  : alvoFibo2;
      double moedaN = (n == 1) ? alvoMoeda1 : alvoMoeda2;

      double volume = NormalizaVolume(loteN);
      if(volume < volMin) continue;

      double preco = 0.0;
      if(fiboN > 0)
      {
         double dist = MathFloor((amplitude*(fiboN/100.0))/tickSize)*tickSize;
         preco = isBuy ? precoEntrada + dist : precoEntrada - dist;
      }
      else if(moedaN > 0)
         preco = CalculaTpMoeda(isBuy,entryPrice,volume,moedaN);
      if(preco <= 0) continue;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action       = TRADE_ACTION_PENDING;
      req.magic        = magicAlvo;
      req.volume       = volume;
      req.price        = NormalizaPreco(preco);
      req.type         = isBuy ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;
      req.type_filling = fillingPadrao;
      req.type_time    = tipoTempo;
      EnviaRequest(req,res,"Alvo "+IntegerToString(n));
   }
}

//+------------------------------------------------------------------+
//| Stop                                                             |
//+------------------------------------------------------------------+

//| Traz o StopLoss real para a extrema da última vela, quando o fechamento
//| violou o Stop fantasma. Entre uma vela e outra a única proteção é o stop
//| de catástrofe enviado junto com a entrada.
void ColocaStop()
{
   if(!MinhaPosicao()) return;
   bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double novo  = isBuy ? rates[1].low - tickSize : rates[1].high + tickSize;
   novo = RespeitaNivelStops(novo, isBuy ? lastTick.bid : lastTick.ask, isBuy);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_SLTP;
   req.magic    = magicEntrada;
   req.position = PositionGetInteger(POSITION_TICKET);
   req.sl       = novo;
   req.tp       = PositionGetDouble(POSITION_TP);   // preserva o TP existente
   if(EnviaRequest(req,res,"Ajuste de StopLoss"))
      ObjectDelete(0,"StopFantasma");
}

//| Move o stop para o zero a zero (mais o gap) quando o gatilho em Fibo ou
//| em moeda é atingido. Nunca piora um stop já existente.
void Breakeven()
{
   double stopLoss    = PositionGetDouble(POSITION_SL);
   double entradaReal = PositionGetDouble(POSITION_PRICE_OPEN);
   double lucro       = PositionGetDouble(POSITION_PROFIT);
   bool   isBuy       = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

   // Já está no zero a zero ou além
   if(isBuy  && stopLoss > 0 && stopLoss >= entradaReal) return;
   if(!isBuy && stopLoss > 0 && stopLoss <= entradaReal) return;

   double novoStop = 0.0;
   if(breakEvenFibo > 0)
   {
      double gatilho = MathFloor((MathAbs(precoTarget - precoStop)*(breakEvenFibo/100.0))/tickSize)*tickSize;
      if(isBuy  && rates[0].high >= precoEntrada + gatilho) novoStop = entradaReal + beGap;
      if(!isBuy && rates[0].low  <= precoEntrada - gatilho) novoStop = entradaReal - beGap;
   }
   else if(breakEvenMoeda > 0 && lucro >= breakEvenMoeda)
      novoStop = isBuy ? entradaReal + beGap : entradaReal - beGap;

   if(novoStop == 0.0) return;
   novoStop = RespeitaNivelStops(novoStop, isBuy ? lastTick.bid : lastTick.ask, isBuy);

   // Não piorar um stop que já existe
   if(isBuy  && stopLoss > 0 && novoStop <= stopLoss) return;
   if(!isBuy && stopLoss > 0 && novoStop >= stopLoss) return;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_SLTP;
   req.magic    = magicEntrada;
   req.position = PositionGetInteger(POSITION_TICKET);
   req.sl       = novoStop;
   req.tp       = PositionGetDouble(POSITION_TP);
   if(EnviaRequest(req,res,"Breakeven"))
      Print("Breakeven acionado em ",novoStop);
}

//+------------------------------------------------------------------+
//| Risco, alvos em moeda e utilidades                               |
//+------------------------------------------------------------------+

//| Define lote1 e lote2 a partir do risco (ou dos lotes fixos, quando
//| riscoMoeda e riscoPorCento são zero). Devolve false quando não dá para
//| entrar dentro do risco pedido - e aí não se entra, em vez de arredondar
//| para cima como a v1.14 fazia com o piso de 2 contratos.
bool CalculaLotes()
{
   if(riscoMoeda <= 0 && riscoPorCento <= 0)
   {
      lote1 = NormalizaVolume(Lote1);
      lote2 = NormalizaVolume(Lote2);
      if(lote1 < volMin && lote2 < volMin)
      {
         Print("Lote1 e Lote2 estão abaixo do volume mínimo do símbolo (",volMin,").");
         return(false);
      }
      if(lote1 < volMin) { lote1 = lote2; lote2 = 0; }
      if(lote2 < volMin) lote2 = 0;
      return(true);
   }

   double valor = (riscoMoeda > 0) ? riscoMoeda
                                   : AccountInfoDouble(ACCOUNT_BALANCE)*(riscoPorCento/100.0);
   // Distância até o stop medida a partir do PIOR preenchimento possível.
   double referencia = (precoPiorFill > 0) ? precoPiorFill : precoEntrada;
   double dist  = MathAbs(referencia - precoStop);
   if(valor <= 0 || dist <= 0 || tickSize <= 0 || tickValue <= 0)
   {
      Print("CalculaLotes: risco, distância de stop ou dados do símbolo inválidos ",
            "(risco=",valor," distância=",dist,").");
      return(false);
   }

   double total = NormalizaVolume(valor/(dist*(tickValue/tickSize)));
   if(total < volMin)
   {
      Print("O risco pedido (",valor,") não paga o volume mínimo (",volMin,
            ") com stop de ",dist,". Entrada cancelada.");
      return(false);
   }

   lote1 = NormalizaVolume(total/2.0);
   if(lote1 < volMin) lote1 = volMin;
   lote2 = NormalizaVolume(total - lote1);
   if(lote2 < volMin) lote2 = 0.0;

   // Margem conferida aqui, e não descoberta pelo servidor como
   // TRADE_RETCODE_NO_MONEY depois do envio.
   double margem = 0.0;
   double preco  = (sinal == 2) ? lastTick.ask : lastTick.bid;
   ENUM_ORDER_TYPE tipo = (sinal == 2) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcMargin(tipo,simbolo,lote1+lote2,preco,margem))
   {
      double livre = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margem > livre)
      {
         Print("Margem necessária (",margem,") acima da margem livre (",livre,
               "). Entrada cancelada.");
         return(false);
      }
   }
   return(true);
}

//| Converte um alvo em moeda da conta para preço.
//| Para compra: lucro = (TP - entrada)*(tickValue/tickSize)*volume
//|   => TP = entrada + lucro/((tickValue/tickSize)*volume)
double CalculaTpMoeda(bool isBuy, double entryPrice, double volume, double alvoMoeda)
{
   if(alvoMoeda <= 0 || volume <= 0 || tickSize <= 0 || tickValue <= 0) return(0);
   double dist = alvoMoeda/((tickValue/tickSize)*volume);
   return(NormalizaPreco(isBuy ? entryPrice + dist : entryPrice - dist));
}

//| Desenha a linha do Stop fantasma. É só gráfico: uma tentativa, e se
//| falhar segue em frente. Até a v1.14 era um laço sem sleep que podia
//| travar a thread do EA no meio do caminho de envio de ordem.
void StopFantasma(double sl)
{
   ObjectDelete(0,"StopFantasma");
   if(!ObjectCreate(0,"StopFantasma",OBJ_HLINE,0,0,sl))
   {
      Print("Não foi possível desenhar o Stop fantasma. Erro = ",GetLastError());
      return;
   }
   ObjectSetInteger(0,"StopFantasma",OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,"StopFantasma",OBJPROP_COLOR,clrRed);
   ChartRedraw(0);
}

//| Soma o resultado LÍQUIDO do dia (lucro + comissão + taxa + swap), só dos
//| negócios deste EA neste símbolo. Recalcula apenas quando entra negócio
//| novo - a v1.14 varria o histórico inteiro a cada tick.
bool BateuMeta()
{
   if(meta <= 0) return(false);

   datetime agora = TimeCurrent();
   datetime dia   = agora - (agora % 86400);
   if(dia != metaDia) { metaDia = dia; metaSaldo = 0; metaDeals = -1; }

   if(!HistorySelect(dia,agora+1)) return(false);
   int total = HistoryDealsTotal();
   if(total != metaDeals)
   {
      metaDeals = total;
      metaSaldo = 0;
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if(HistoryDealGetString(ticket,DEAL_SYMBOL) != simbolo) continue;
         long m = HistoryDealGetInteger(ticket,DEAL_MAGIC);
         if(m != magicEntrada && m != magicAlvo) continue;
         long tipo = HistoryDealGetInteger(ticket,DEAL_TYPE);
         if(tipo != DEAL_TYPE_BUY && tipo != DEAL_TYPE_SELL) continue;
         metaSaldo += HistoryDealGetDouble(ticket,DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket,DEAL_COMMISSION)
                    + HistoryDealGetDouble(ticket,DEAL_FEE)
                    + HistoryDealGetDouble(ticket,DEAL_SWAP);
      }
   }

   if(metaSaldo > meta)
   {
      Comment("Meta diária alcançada! CARPE DIEM Guerreiro!");
      return(true);
   }
   return(false);
}

//| Fecha a posição a mercado, com número limitado de tentativas. A v1.14
//| usava while(PositionSelect(...)) sem limite - e era chamada justamente
//| fora do horário, quando o mercado costuma estar fechado.
void FechaPosicao()
{
   for(int tentativa = 0; tentativa < InpMaxTentativas; tentativa++)
   {
      if(!MinhaPosicao()) return;

      long tipo = PositionGetInteger(POSITION_TYPE);
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action       = TRADE_ACTION_DEAL;
      req.magic        = magicEntrada;
      req.position     = PositionGetInteger(POSITION_TICKET);
      req.volume       = PositionGetDouble(POSITION_VOLUME);
      req.type         = (tipo == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price        = NormalizaPreco((tipo == POSITION_TYPE_BUY) ? lastTick.bid : lastTick.ask);
      req.deviation    = InpDesvioPontos;
      req.type_filling = fillingPadrao;

      if(!EnviaRequest(req,res,"Fechamento de posição")) return;
      Sleep(200);
      SymbolInfoTick(simbolo,lastTick);
   }
}

//| Detecta vela nova pelo tempo de abertura da barra corrente. Bars() não
//| serve: com o limite de barras do gráfico atingido, entra uma barra e sai
//| outra, a contagem não muda e a vela nova nunca era detectada.
bool NovaVela()
{
   datetime t = iTime(simbolo,periodo,0);
   if(t <= 0 || t == tempoUltimaVela) return(false);
   tempoUltimaVela = t;
   return(true);
}

//| Verifica se o horário do servidor está dentro da janela de trabalho.
//| Suporta janela que cruza a meia-noite (stop < start).
bool TimeSession(int aStartHour,int aStartMinute,int aStopHour,int aStopMinute,datetime aTimeCur)
{
   int StartTime = 3600*aStartHour + 60*aStartMinute;
   int StopTime  = 3600*aStopHour  + 60*aStopMinute;
   aTimeCur = aTimeCur % 86400;

   if(StopTime < StartTime)
      return(aTimeCur >= StartTime || aTimeCur < StopTime);
   return(aTimeCur >= StartTime && aTimeCur < StopTime);
}

//+------------------------------------------------------------------+
//| Critério de otimização                                           |
//+------------------------------------------------------------------+

//| Devolve o resultado LÍQUIDO da passada, e zero quando a configuração
//| não atinge o piso de edge por contrato.
//|
//| Otimizador que maximiza lucro bruto escolhe justamente as configurações
//| que só ganham no preenchimento otimista do tester - quanto mais trades,
//| mais ele gosta. Por isso o critério é líquido de custo e há um piso de
//| edge medido em ticks, que é a granularidade física do preço.
double OnTester()
{
   if(!HistorySelect(0,TimeCurrent())) return(0.0);

   double liquido = 0.0, volumeSaida = 0.0;
   int    saidas  = 0;
   int    total   = HistoryDealsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      long tipo = HistoryDealGetInteger(ticket,DEAL_TYPE);
      if(tipo != DEAL_TYPE_BUY && tipo != DEAL_TYPE_SELL) continue;

      liquido += HistoryDealGetDouble(ticket,DEAL_PROFIT)
               + HistoryDealGetDouble(ticket,DEAL_COMMISSION)
               + HistoryDealGetDouble(ticket,DEAL_FEE)
               + HistoryDealGetDouble(ticket,DEAL_SWAP);

      long entrada = HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(entrada == DEAL_ENTRY_OUT || entrada == DEAL_ENTRY_INOUT)
      {
         saidas++;
         volumeSaida += HistoryDealGetDouble(ticket,DEAL_VOLUME);
      }
   }

   // Amostra pequena não decide nada
   if(saidas < InpMinTrades || volumeSaida <= 0 || tickValue <= 0) return(0.0);

   double edgeTicks = liquido/(volumeSaida*tickValue);
   if(edgeTicks < InpPisoEdgeTicks)
   {
      Print("OnTester: edge líquido de ",DoubleToString(edgeTicks,3),
            " tick/contrato abaixo do piso de ",InpPisoEdgeTicks,". Configuração reprovada.");
      return(0.0);
   }
   Print("OnTester: ",saidas," saídas, líquido ",DoubleToString(liquido,2),
         ", edge ",DoubleToString(edgeTicks,3)," tick/contrato.");
   return(liquido);
}
