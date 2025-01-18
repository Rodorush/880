//+------------------------------------------------------------------+
//|                                                 880 (v.1.09).mq5 |
//|                                       Rodolfo Pereira de Andrade |
//|                                    https://rodorush.blogspot.com |
//+------------------------------------------------------------------+
#property copyright "Rodolfo Pereira de Andrade"
#property link      "https://rodorush.blogspot.com"
#property version   "1.09"

bool contaHedge;
double lote1, lote2;
double maFast[], maSlow[], stoch[];
double precoEntrada, precoStop;
double precoTarget;
double tickSize;
double tickValue;
double spread;
double stopInit;
ENUM_TIMEFRAMES periodo;
int maHandle_fast, maHandle_slow, stochHandle;
int sinal;

MqlRates rates[];
MqlTick lastTick;
MqlTradeRequest myRequest = {};
MqlTradeResult myResult = {};

string robot = "880 1.08"; //Nome do EA
string simbolo;

input group "Parâmetros"
input double meta = 0; //Meta diária em moeda. Se 0 não usa
input double breakEven = 161.8; //Gatilho para BreakEven em porcentagem de Fibo
input double breakEvenGap = 5; //Valor do BreakEven em pontos da entrada real
input double stopInicial = 2000.0; //Stop inicial em pontos
input bool usaStoch = false; //Usa Estocástico?

input group "Alvos"
input double riscoMoeda = 0; //Risco em moeda. Se 0 não usa
input double riscoPorCento = 1; //Risco em %
input double alvo1 = 161.8; //Alvo 1 em porcentagem de Fibo
input double Lote1 = 0.1;   //Lotes para Alvo 1
input double alvo2 = 200;   //Alvo 2 em porcentagem de Fibo
input double Lote2 = 0.1;   //Lotes para Alvo 2

input group "Fast MA"
input int ma_period_fast = 8; 
input int ma_shift_fast = 0; 
input ENUM_MA_METHOD ma_method_fast = MODE_EMA; 
input ENUM_APPLIED_PRICE applied_price_fast = PRICE_CLOSE; 

input group "Slow MA"
input int ma_period_slow = 80; 
input int ma_shift_slow = 0; 
input ENUM_MA_METHOD ma_method_slow = MODE_EMA; 
input ENUM_APPLIED_PRICE applied_price_slow = PRICE_CLOSE; 

input group "Estocástico Lento"
input int Kperiod = 14; 
input int Dperiod = 3; 
input int slowing = 3; 
input ENUM_MA_METHOD ma_method = MODE_SMA; 
input ENUM_STO_PRICE price_field = STO_LOWHIGH; 

input group "Níveis Estocástico"
input int sc = 80; //Sobrecompra
input int sv = 20; //Sobrevenda

input group "Horário de Funcionamento"
input int  startHour = 9;      //Hora de início dos trades
sinput int startMinutes = 0;   //Minutos de início (fora da otimização)
input int  stopHour = 17;      //Hora de interrupção
sinput int stopMinutes = 45;   //Minutos de interrupção (fora da otimização)

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Verifica restrição de lote mínimo 0.01
   double minLot = 0;
   if(!SymbolInfoDouble(ChartSymbol(0),SYMBOL_VOLUME_MIN,minLot))
   {
      Print("Não foi possível ler o lote mínimo do símbolo. Encerrando EA...");
      ExpertRemove();
      return(INIT_FAILED);
   }
   if(minLot > 0.01)
   {
      Print("AVISO: A corretora não permite lote de 0.01. Lote mínimo permitido = ", 
            DoubleToString(minLot,_Digits));
      Print("EA será removido devido à restrição de lote mínimo.");
      ExpertRemove();
      return(INIT_FAILED);
   }

   if(startHour > stopHour) return(INIT_PARAMETERS_INCORRECT);

   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      contaHedge = true;
      Print("Robô trabalhando em modo Hedge.");
   }
   else
   {
      contaHedge = false;
      Print("Robô trabalhando em modo Netting.");
   }
   stopInit = stopInicial;
   
   ArraySetAsSeries(maFast,true);
   ArraySetAsSeries(maSlow,true);
   ArraySetAsSeries(stoch,true);
   ArraySetAsSeries(rates,true);

   simbolo = ChartSymbol(0);
   periodo = ChartPeriod(0);
   tickSize = SymbolInfoDouble(simbolo,SYMBOL_TRADE_TICK_SIZE);
   tickValue = SymbolInfoDouble(simbolo,SYMBOL_TRADE_TICK_VALUE);
   spread   = SymbolInfoInteger(Symbol(),SYMBOL_SPREAD)*tickSize;
              
   SymbolInfoTick(simbolo,lastTick);
   CopyRates(simbolo, periodo, 0, 3, rates);

   myRequest.symbol      = simbolo;
   myRequest.deviation   = 0;
   myRequest.type_filling= ORDER_FILLING_RETURN;
   myRequest.type_time   = ORDER_TIME_DAY;
   myRequest.comment     = robot;
   
   //Identificando valores de ordens manuais abertas para gestão
   if(PositionSelect(simbolo))
   {
      precoEntrada = GlobalVariableGet("precoEntrada"+simbolo);
      precoStop    = GlobalVariableGet("precoStop"+simbolo);
      if(precoEntrada == 0)
      {
         MessageBox("Não há preço de Entrada definido p/ a posição ativa. Informe e tente novamente.");
         ExpertRemove();
      }
      else if(precoStop == 0)
      {
         MessageBox("Não há preço de Stop definido p/ a posição ativa. Informe e tente novamente.");
         ExpertRemove();
      }
      else if(PositionGetDouble(POSITION_SL) == 0)
      {
         MessageBox("Não há StopLoss definido p/ a posição ativa. Crie esse Stop e tente novamente.");
         ExpertRemove();
      }
      StopFantasma((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) 
                    ? precoStop - tickSize : precoStop + tickSize);
   }
   else
   {
      precoEntrada = 0;
      precoStop    = 0;
      GlobalVariableSet("precoEntrada"+simbolo,0);
      GlobalVariableSet("precoStop"+simbolo,0);
   }
   
   // Inicializa indicadores
   maHandle_fast = iMA(simbolo, periodo, ma_period_fast, ma_shift_fast, ma_method_fast, applied_price_fast);
   maHandle_slow = iMA(simbolo, periodo, ma_period_slow, ma_shift_slow, ma_method_slow, applied_price_slow);
   stochHandle   = iStochastic(simbolo, periodo, Kperiod, Dperiod, slowing, ma_method, price_field);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   int bars = Bars(simbolo, periodo);
   SymbolInfoTick(simbolo,lastTick);
   CopyRates(simbolo, periodo, 0, 3, rates);

   // Se Netting, respeita janelas
   if(!contaHedge)
   {
      if(!TimeSession(startHour,startMinutes,stopHour,stopMinutes,TimeCurrent()))
      {
         DeletaOrdem();
         FechaPosicao();
         DeletaAlvo();
         Comment("Fora do horário de trabalho. EA dormindo...");
      }
      else
      {
         Comment("");
      }
   }
   
   // Se não tem posição e bateu meta, para
   if(PositionsTotal() == 0)
      if(BateuMeta()) return;

   // A cada nova vela
   if(NovaVela(bars))
   {
      IndBuffers();

      // Se já existe posição aberta
      if(PositionSelect(simbolo))
      {
         // Ajusta Stop caso o preço chegue a violar Stop fantasma
         if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && rates[1].close < precoStop) ||
            (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && rates[1].close > precoStop))
         {
            if(contaHedge) ColocaStopHedge(); 
            else ColocaStop();
         }
      }
      else
      {
         // Não existe posição
         if(Sinal())
         {
            if(contaHedge) ColocaOrdemHedge(); 
            else ColocaOrdem();
         }
         else
         {
            if(contaHedge) DeletaOrdemHedge(); 
            else DeletaOrdem();
         }
      }
   }

   // Se existe posição, verifica breakeven e alvos
   if(contaHedge)
   {
      if(PositionSelect(simbolo)) 
         BreakevenHedge();
   }
   else
   {
      if(PositionSelect(simbolo))
      {
         Breakeven();
         // Se não há ordens de alvo e volume está inteiro
         if(OrdersTotal() == 0 && PositionGetDouble(POSITION_VOLUME) == (lote1 + lote2))
            ColocaAlvo();
      }
      else
      {
         DeletaAlvo(); 
      }
   }
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   if(contaHedge) DeletaOrdemHedge(); 
   else DeletaOrdem();

   GlobalVariableSet("precoEntrada"+simbolo,precoEntrada);
   GlobalVariableSet("precoStop"+simbolo,   precoStop);
   MessageBox("EA removido com sucesso!",NULL,MB_OK);
}

//+------------------------------------------------------------------+
//| Funções de apoio                                                |
//+------------------------------------------------------------------+
void IndBuffers()
{
   CopyBuffer(maHandle_fast,0,0,3,maFast);
   CopyBuffer(maHandle_slow,0,0,3,maSlow);
   CopyBuffer(stochHandle,0,0,3,stoch);
}

bool Sinal()
{
   sinal = 0;
   // Compra
   if(maFast[1] > maSlow[1])
   {
      if(
         (rates[2].close < maFast[2] && rates[1].close > maFast[1]) ||
         (rates[2].high >  rates[1].high && (rates[1].open > maFast[1] || rates[1].close > maFast[1])) ||
         (usaStoch && stoch[1] < sv)
        )
      {
         sinal = 2;
      }
   }
   // Venda
   else if(maFast[1] < maSlow[1])
   {
      if(
         (rates[2].close > maFast[2] && rates[1].close < maFast[1]) ||
         (rates[2].low <   rates[1].low  && (rates[1].open < maFast[1] || rates[1].close < maFast[1])) ||
         (usaStoch && stoch[1] > sc)
        )
      {
         sinal = -2;
      }
   }
   return(sinal == 2 || sinal == -2);
}

int InsideBar()
{
   // Se candle anterior "engloba" o candle recente
   if(rates[2].high > rates[1].high && rates[2].low < rates[1].low) 
      return(2);
   return(1);
}

//+------------------------------------------------------------------+
//| Coloca ordem pendente (Netting)                                 |
//+------------------------------------------------------------------+
void ColocaOrdem()
{
   int inside = InsideBar();
   if(OrdersTotal() == 1) DeletaOrdem(); // Remove pendente anterior

   // Prepara variáveis
   precoEntrada = (sinal == 2) ? rates[1].high : rates[1].low;
   GlobalVariableSet("precoEntrada"+simbolo,precoEntrada);

   myRequest.price  = (sinal == 2) ? precoEntrada + tickSize : precoEntrada - tickSize;
   precoStop        = (sinal == 2) ? rates[inside].low : rates[inside].high;
   precoTarget      = (sinal == 2) ? rates[inside].high : rates[inside].low; 
   GlobalVariableSet("precoStop"+simbolo, precoStop);

   StopFantasma((sinal == 2) ? precoStop - tickSize : precoStop + tickSize);
   myRequest.sl = (sinal == 2) ? precoStop - stopInit : precoStop + stopInit;

   myRequest.type = (sinal == 2) 
                    ? ((myRequest.price >= lastTick.ask) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_BUY_LIMIT)
                    : ((myRequest.price <= lastTick.bid) ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_SELL_LIMIT);

   myRequest.action = TRADE_ACTION_PENDING;

   if(riscoMoeda > 0 || riscoPorCento > 0)
      CalculaLotes();
   else
   {
      lote1 = Lote1;
      lote2 = Lote2;
   }

   myRequest.volume = lote1 + lote2;

   bool orderSent;
   do
   {
      orderSent = OrderSend(myRequest,myResult);
      if(!orderSent) Print("Envio de ordem de entrada falhou. Erro = ",GetLastError());
      Sleep(100);
      SymbolInfoTick(simbolo,lastTick);
      CopyRates(simbolo, periodo, 0, 3, rates);
   }
   while(!orderSent);
}

//+------------------------------------------------------------------+
//| Coloca ordem pendente (Hedge)                                   |
//+------------------------------------------------------------------+
void ColocaOrdemHedge()
{
   int inside = InsideBar();
   DeletaOrdemHedge(); // Remove pendente anterior

   precoEntrada = (sinal == 2) ? rates[1].high : rates[1].low; 
   GlobalVariableSet("precoEntrada"+simbolo, precoEntrada);

   myRequest.price  = (sinal == 2) ? precoEntrada + tickSize + spread : precoEntrada - tickSize;
   precoStop        = (sinal == 2) ? rates[inside].low : rates[inside].high; 
   GlobalVariableSet("precoStop"+simbolo, precoStop);

   StopFantasma((sinal == 2) ? precoStop - tickSize : precoStop + tickSize);
   myRequest.sl = (sinal == 2) ? precoStop - stopInit : precoStop + stopInit;
   
   myRequest.type = (sinal == 2)
                    ? ((myRequest.price >= lastTick.ask) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_BUY_LIMIT)
                    : ((myRequest.price <= lastTick.bid) ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_SELL_LIMIT);

   myRequest.action = TRADE_ACTION_PENDING;

   if(riscoMoeda > 0 || riscoPorCento > 0)
      CalculaLotes();
   else
   {
      lote1 = Lote1;
      lote2 = Lote2;
   }

   // --- 1ª ordem (lote1)
   myRequest.volume = lote1;
   double target = MathFloor(((rates[inside].high - rates[inside].low)*(alvo1/100.0))/tickSize)*tickSize;
   myRequest.tp    = (sinal == 2 && alvo1>0) ? (rates[1].high + target) 
                                            : ((sinal == 2) ? 0 : (rates[1].low - target)); 
   // Se alvo1=0 e sinal é de compra, tp=0 (sem TP). 
   // (Para venda e alvo1>0 ajustaria analogamente, mas acima exemplificado)

   bool orderSent;
   do
   {
      orderSent = OrderSend(myRequest,myResult);
      if(!orderSent) Print("Envio de ordem (1ª posição) falhou. Erro = ",GetLastError());
      Sleep(100);
      SymbolInfoTick(simbolo,lastTick);
      CopyRates(simbolo, periodo, 0, 3, rates);
   }
   while(!orderSent);

   // --- 2ª ordem (lote2) só se lote2>0
   if(lote2 > 0)
   {
      myRequest.volume = lote2;

      // Se alvo2>0, calculamos TP. Se alvo2=0 => TP=0
      if(alvo2 > 0)
      {
         target = MathFloor(((rates[inside].high - rates[inside].low)*(alvo2/100.0))/tickSize)*tickSize;
         myRequest.tp = (sinal == 2) ? (rates[1].high + target) 
                                     : (rates[1].low  - target);
      }
      else
      {
         myRequest.tp = 0; // sem alvo
      }
      
      do
      {
         orderSent = OrderSend(myRequest,myResult);
         if(!orderSent) Print("Envio de ordem (2ª posição) falhou. Erro = ",GetLastError());
         Sleep(100);
         SymbolInfoTick(simbolo,lastTick);
         CopyRates(simbolo, periodo, 0, 3, rates);
      }
      while(!orderSent);
   }
}

//+------------------------------------------------------------------+
//| Coloca Alvo(s) no modo Netting                                  |
//+------------------------------------------------------------------+
void ColocaAlvo()
{
   // Só faz sentido colocar ordens-limite se houve volume (lote1 ou lote2)
   int inside = InsideBar();
   long positionType = PositionGetInteger(POSITION_TYPE);

   myRequest.action = TRADE_ACTION_PENDING;
   myRequest.sl     = 0;
   myRequest.type   = (positionType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;

   // --- Alvo 1 se lote1>0 && alvo1>0
   if(lote1 > 0 && alvo1 > 0)
   {
      double target1 = MathFloor(((rates[inside].high - rates[inside].low)*(alvo1/100.0))/tickSize)*tickSize;
      myRequest.volume= lote1;
      myRequest.price = (positionType == POSITION_TYPE_BUY) 
                        ? (rates[1].high + target1) 
                        : (rates[1].low  - target1);

      Print("Colocando Alvo 1...");
      if(!OrderSend(myRequest,myResult)) 
         Print("Envio de ordem Alvo 1 falhou. Erro = ",GetLastError());
   }

   // --- Alvo 2 se lote2>0 && alvo2>0
   if(lote2 > 0 && alvo2 > 0)
   {
      double target2 = MathFloor(((rates[inside].high - rates[inside].low)*(alvo2/100.0))/tickSize)*tickSize;
      myRequest.volume= lote2;
      myRequest.price = (positionType == POSITION_TYPE_BUY) 
                        ? (rates[1].high + target2) 
                        : (rates[1].low  - target2);

      Print("Colocando Alvo 2...");
      if(!OrderSend(myRequest,myResult)) 
         Print("Envio de ordem Alvo 2 falhou. Erro = ",GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Coloca Stop (Netting)                                           |
//+------------------------------------------------------------------+
void ColocaStop()
{
   myRequest.action = TRADE_ACTION_SLTP;
   myRequest.sl = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) 
                  ? rates[1].low  - tickSize 
                  : rates[1].high + tickSize;

   if(!OrderSend(myRequest,myResult)) 
      Print("Inclusão de Stop no Trade falhou. Erro = ",GetLastError());
   ObjectDelete(0,"StopFantasma");
}

//+------------------------------------------------------------------+
//| Coloca Stop (Hedge)                                             |
//+------------------------------------------------------------------+
void ColocaStopHedge()
{
   myRequest.action = TRADE_ACTION_SLTP;
   myRequest.sl = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) 
                  ? rates[1].low  - tickSize 
                  : rates[1].high + tickSize + spread;

   int positionsTotal = PositionsTotal();
   for(int i = 0; i < positionsTotal; i++)
   {
      if(PositionGetSymbol(i) == simbolo)
      {
         myRequest.position = PositionGetTicket(i);
         if(!OrderSend(myRequest,myResult)) 
            Print("Inclusão de Stop no Trade ",(i+1)," falhou. Erro = ",GetLastError());
      }
   }
   ObjectDelete(0,"StopFantasma");
}

//+------------------------------------------------------------------+
//| Breakeven (Netting)                                             |
//+------------------------------------------------------------------+
void Breakeven()
{
   double stopLoss    = PositionGetDouble(POSITION_SL);
   double target      = MathFloor((MathAbs(precoTarget - precoStop)*(breakEven/100.0))/tickSize)*tickSize;
   double entradaReal = PositionGetDouble(POSITION_PRICE_OPEN);

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      if(stopLoss >= entradaReal) return;
      if(rates[0].high >= precoEntrada + target)
         myRequest.sl = entradaReal + breakEvenGap; 
      else
         return;
   }
   else
   {
      if(stopLoss <= entradaReal) return;
      if(rates[0].low <= precoEntrada - target)
         myRequest.sl = entradaReal - breakEvenGap; 
      else
         return;
   }
   myRequest.position = PositionGetTicket(0); 
   myRequest.action   = TRADE_ACTION_SLTP;
   
   Print("Acionando Breakeven...");
   if(!OrderSend(myRequest,myResult)) 
      Print("Ordem Breakeven falhou. Erro = ",GetLastError());
}

//+------------------------------------------------------------------+
//| Breakeven (Hedge)                                               |
//+------------------------------------------------------------------+
void BreakevenHedge()
{
   double stopLoss    = PositionGetDouble(POSITION_SL);
   double target      = MathFloor((MathAbs(precoEntrada - precoStop)*(breakEven/100.0))/tickSize)*tickSize;
   double entradaReal = PositionGetDouble(POSITION_PRICE_OPEN);

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      if(stopLoss >= entradaReal) return; 
      if(rates[0].high >= precoEntrada + target)
         myRequest.sl = entradaReal + breakEvenGap; 
      else
         return; 
   }
   else
   {
      if(stopLoss <= entradaReal) return; 
      if(rates[0].low <= precoEntrada - target)
         myRequest.sl = entradaReal - breakEvenGap; 
      else
         return; 
   }

   myRequest.action = TRADE_ACTION_SLTP;
   int positionsTotal = PositionsTotal();
   for(int i = 0; i < positionsTotal; i++)
   {
      if(PositionGetSymbol(i) == simbolo)
      {
         myRequest.position = PositionGetTicket(i);
         myRequest.tp       = PositionGetDouble(POSITION_TP);
         Print("Acionando Breakeven na posição ", (i+1), "...");
         if(!OrderSend(myRequest,myResult)) 
            Print("Ordem Breakeven falhou. Erro = ",GetLastError());
      }
   }
   ObjectDelete(0,"StopFantasma");
}

//+------------------------------------------------------------------+
//| Deleta ordem pendente (Netting)                                 |
//+------------------------------------------------------------------+
void DeletaOrdem()
{
   if(OrdersTotal() == 1)
   {
      myRequest.position = 0;
      myRequest.action   = TRADE_ACTION_REMOVE;
      myRequest.order    = OrderGetTicket(0);
      Print("Deletando Ordem Pendente...");
      if(!OrderSend(myRequest,myResult)) 
         Print("Deleção falhou. Erro = ",GetLastError());
   }

   if(!PositionSelect(simbolo))
   {
      precoEntrada = 0;
      precoStop    = 0;
      ObjectDelete(0,"StopFantasma");
   }
}

//+------------------------------------------------------------------+
//| Deleta ordem pendente (Hedge)                                   |
//+------------------------------------------------------------------+
void DeletaOrdemHedge()
{
   ulong ticket;
   myRequest.position = 0;
   myRequest.action   = TRADE_ACTION_REMOVE;
   int ordersTotal    = OrdersTotal();

   for(int i = ordersTotal-1; i >= 0; i--)
   {
      ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == simbolo)
      {
         myRequest.order = ticket;
         Print("Deletando ordem pendente na posição: ",i);
         if(!OrderSend(myRequest,myResult)) 
            Print("Falha ao deletar ordem ",ticket," Erro = ",GetLastError());
      }
   }

   if(!PositionSelect(simbolo))
   {
      precoEntrada = 0;
      precoStop    = 0;
   }
   ObjectDelete(0,"StopFantasma");
}

//+------------------------------------------------------------------+
//| Deleta alvos se existirem (Netting)                             |
//+------------------------------------------------------------------+
void DeletaAlvo()
{
   int ordersTotal = OrdersTotal();
   for(int i = ordersTotal-1; i >= 0; i--)
   {
      ulong orderTicket = OrderGetTicket(i);
      if(orderTicket > 0)
      {
         long orderType = OrderGetInteger(ORDER_TYPE);
         if(orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_SELL_LIMIT)
         {
            myRequest.position = 0;
            myRequest.action   = TRADE_ACTION_REMOVE;
            myRequest.order    = orderTicket;
            Print("Deletando Alvo/Limit pendente...");
            if(!OrderSend(myRequest,myResult)) 
               Print("Deleção falhou. Erro = ",GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cálculo de lotes a partir do risco                              |
//+------------------------------------------------------------------+
void CalculaLotes()
{
   double valor = (riscoMoeda > 0) 
                  ? riscoMoeda 
                  : AccountInfoDouble(ACCOUNT_BALANCE)*(riscoPorCento/100);

   double lotes;
   if(contaHedge)
   {
      // Hedge => dividimos em duas ordens
      lotes = valor / (MathAbs(precoEntrada - precoStop)*(tickValue/tickSize));
      lotes = MathRound((lotes/10)*100);
      if(MathMod(lotes,2)!=0) lotes++;
      lote1 = MathMax((lotes/2)*0.1,0.1);
      lote2 = lote1;
   }
   else
   {
      // Netting => abrimos 1 posição com (lote1 + lote2)
      lotes = MathRound(valor / (MathAbs(precoEntrada - precoStop)*(tickValue/tickSize)));
      if(MathMod(lotes,2)!=0) lotes++;
      lote1 = MathMax(lotes/2,1);
      lote2 = lote1;
   }
}

//+------------------------------------------------------------------+
//| Desenha linha de "Stop Fantasma"                                |
//+------------------------------------------------------------------+
void StopFantasma(double sl)
{
   bool falhou = true;
   while(falhou && !IsStopped())
   {
      if(ObjectCreate(0,"StopFantasma",OBJ_HLINE,0,0,sl))
         if(ObjectFind(0,"StopFantasma") == 0)
            if(ObjectSetInteger(0,"StopFantasma",OBJPROP_STYLE,STYLE_DASH))
               if(ObjectGetInteger(0,"StopFantasma",OBJPROP_STYLE) == STYLE_DASH)
                  if(ObjectSetInteger(0,"StopFantasma",OBJPROP_COLOR,clrRed))
                     if(ObjectGetInteger(0,"StopFantasma",OBJPROP_COLOR) == clrRed)
                     {
                        ChartRedraw(0);
                        falhou = false;
                     }
   }
}

//+------------------------------------------------------------------+
//| Verifica se a meta diária foi alcançada                         |
//+------------------------------------------------------------------+
bool BateuMeta()
{
   double saldo = 0;
   datetime now   = TimeCurrent();
   datetime today = (now / 86400) * 86400; // Início do dia em UnixTime

   if(meta == 0) return(false);

   if(HistorySelect(today,now))
   {
      int historyDealsTotal = HistoryDealsTotal();
      for(int i = historyDealsTotal; i > 0; i--)
         saldo += HistoryDealGetDouble(HistoryDealGetTicket(i-1),DEAL_PROFIT);
   }
   else
      Print("Erro ao obter histórico de ordens e trades!");

   if(saldo > meta)
   {
      Comment("Meta diária alcançada! CARPE DIEM Guerreiro!");
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Fecha posição do símbolo atual                                  |
//+------------------------------------------------------------------+
void FechaPosicao()
{
   while(PositionSelect(simbolo))
   {
      long positionType      = PositionGetInteger(POSITION_TYPE);
      myRequest.action       = TRADE_ACTION_DEAL;
      myRequest.volume       = PositionGetDouble(POSITION_VOLUME);
      myRequest.type         = (positionType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      myRequest.price        = (positionType == POSITION_TYPE_BUY) ? lastTick.bid : lastTick.ask;
      myRequest.sl           = 0;
      myRequest.tp           = 0;
      myRequest.position     = PositionGetInteger(POSITION_TICKET);

      Print("Fechando posição...");
      if(!OrderSend(myRequest,myResult)) 
         Print("Envio de ordem Fechamento falhou. Erro = ",GetLastError());
      Sleep(100);
      SymbolInfoTick(simbolo,lastTick);
   }   
}

//+------------------------------------------------------------------+
//| Verifica se é uma nova vela                                     |
//+------------------------------------------------------------------+
bool NovaVela(int bars)
{
   static int lastBars = 0;
   if(bars > lastBars)
   {
      lastBars = bars;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Verifica se estamos na janela de trading                        |
//+------------------------------------------------------------------+
bool TimeSession(int aStartHour,int aStartMinute,int aStopHour,int aStopMinute,datetime aTimeCur)
{
   // start/stop em segundos do dia
   int StartTime = 3600*aStartHour + 60*aStartMinute;
   int StopTime  = 3600*aStopHour  + 60*aStopMinute;
   aTimeCur = aTimeCur % 86400; // segundos decorridos do dia

   if(StopTime < StartTime)
   {
      // passa da meia-noite
      if(aTimeCur >= StartTime || aTimeCur < StopTime)
         return(true);
   }
   else
   {
      // dentro do mesmo dia
      if(aTimeCur >= StartTime && aTimeCur < StopTime)
         return(true);
   }
   return(false);
}
//+------------------------------------------------------------------+