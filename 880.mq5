//+------------------------------------------------------------------+
//|                                                 880 (v.1.01).mq5 |
//|                                       Rodolfo Pereira de Andrade |
//|                                    https://rodorush.blogspot.com |
//+------------------------------------------------------------------+
#property copyright "Rodolfo Pereira de Andrade"
#property link      "https://rodorush.blogspot.com"
#property version   "1.01"

bool contaHedge;
double maFast[], maSlow[], stoch[];
double precoEntrada, precoStop;
double tickSize;
double spread;
double stopInit;
ENUM_TIMEFRAMES periodo;
int maHandle_fast, maHandle_slow, stochHandle;
int sinal;

MqlRates rates[];
MqlTick lastTick;
MqlTradeRequest myRequest = {};
MqlTradeResult myResult = {};

string robot = "880 1.01"; //Nome do EA
string simbolo;

input group "Parâmetros"
input double meta = 2000; //Meta diária em reais. Se 0 não usa
input double breakEven = 161.8; //Gatilho para BreakEven em porcentagem de Fibo
input double breakEvenGap = 5; //Valor do BreakEven em pontos da entrada real

input group "Alvos"
input double alvo1 = 161.8; //Alvo 1 em porcentagem de Fibo
input double lote1 = 1; //Lotes para Alvo 1
input double alvo2 = 200; //Alvo 2 em porcentagem de Fibo
input double lote2 = 1; //Lotes para Alvo 1

input group "Fast MA"
input int ma_period_fast = 8; //Período
input int ma_shift_fast = 0; //Deslocamento horizontal 
input ENUM_MA_METHOD ma_method_fast = MODE_EMA; //Tipo
input ENUM_APPLIED_PRICE applied_price_fast = PRICE_CLOSE; //Tipo do preço

input group "Slow MA"
input int ma_period_slow = 80; //Período
input int ma_shift_slow = 0; //Deslocamento horizontal 
input ENUM_MA_METHOD ma_method_slow = MODE_EMA; //Tipo
input ENUM_APPLIED_PRICE applied_price_slow = PRICE_CLOSE; //Tipo do preço

input group "Estocástico Lento"
input int Kperiod = 8; //K-period (número de barras para cálculos) 
input int Dperiod = 3; //D-period (período da primeira suavização) 
input int slowing = 3; //Final da suavização 
input ENUM_MA_METHOD ma_method = MODE_SMA; //Tipo de suavização 
input ENUM_STO_PRICE price_field = STO_LOWHIGH; //Método de cálculo estocástico 

input group "Níveis Estocástico"
input int sc = 80; //Sobrecompra
input int sv = 20; //Sobrevenda

input group "Horário de Funcionamento"
input int startHour = 9; //Hora de início dos trades
sinput int startMinutes = 00; //Minutos de início dos trades
input int stopHour = 17; //Hora de interrupção dos trades
sinput int stopMinutes = 50; //Minutos de interrupção dos trades

int OnInit() {
   if(startHour > stopHour) return(INIT_PARAMETERS_INCORRECT);
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
      contaHedge = true;
      stopInit = 200.00;
      Print("Robô trabalhando em modo Hedge.");
   }else {
      contaHedge = false;
      stopInit = 100.00;
      Print("Robô trabalhando em modo Netting.");
   }
   
   ArraySetAsSeries(maFast,true);
   ArraySetAsSeries(maSlow,true);
   ArraySetAsSeries(stoch,true);
   ArraySetAsSeries(rates,true);

   simbolo = ChartSymbol(0);
   periodo = ChartPeriod(0);
   tickSize = SymbolInfoDouble(simbolo,SYMBOL_TRADE_TICK_SIZE);
   spread = SymbolInfoInteger(Symbol(),SYMBOL_SPREAD)/100.0;
              
   SymbolInfoTick(simbolo,lastTick);
   CopyRates(simbolo, periodo, 0, 3, rates);

   myRequest.symbol = simbolo;
   myRequest.deviation = 0;
   myRequest.type_filling = ORDER_FILLING_RETURN;
   myRequest.type_time = ORDER_TIME_DAY;
   myRequest.comment = robot;
   
   //Identificando valores de ordens manuais abertas para gestão do risco
   if(PositionSelect(simbolo)) {
      precoEntrada = GlobalVariableGet("precoEntrada");
      precoStop = GlobalVariableGet("precoStop");
      if(precoEntrada == 0) {
         MessageBox("Não há preço de Entrada definido para a posição ativa. Informe esse valor para o manejo de risco e tente novamente. Encerrando EA...");
         ExpertRemove();
      }else if(precoStop == 0) {
         MessageBox("Não há preço de Stop definido para a posição ativa. Informe esse valor para o manejo de risco e tente novamente. Encerrando EA...");
         ExpertRemove();
      }else if(PositionGetDouble(POSITION_SL) == 0) {
         MessageBox("Não há StopLoss definido para a posição ativa. Crie esse Stop para o manejo de risco e tente novamente. Encerrando EA...");
         ExpertRemove();
      }
      StopFantasma((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? precoStop-tickSize : precoStop+tickSize);
   }else{
      precoEntrada = 0;
      precoStop = 0;
      GlobalVariableSet("precoEntrada",0);
      GlobalVariableSet("precoStop",0);
   }
   
   return(INIT_SUCCEEDED);
}

void OnTick() {
   int bars = Bars(simbolo, periodo);
   SymbolInfoTick(simbolo,lastTick);
   CopyRates(simbolo, periodo, 0, 3, rates);

   if(!contaHedge) {
      if(!TimeSession(startHour,startMinutes,stopHour,stopMinutes,TimeCurrent())) {
         DeletaOrdem();
         FechaPosicao();
         DeletaAlvo();
         Comment("Fora do horário de trabalho. EA dormindo...");
      }else Comment("");
   }
   
   if(PositionsTotal() == 0) if(BateuMeta()) return; //? Tentar checar meta por ativo e ver se é melhor colocar dentro de velas para consumir menos recursos.

   if(NovaVela(bars)) {
      IndBuffers();
      if(PositionSelect(simbolo)) {
         if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && rates[1].close < precoStop) ||
          (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && rates[1].close > precoStop))
           if(contaHedge) ColocaStopHedge(); else ColocaStop();
      }else {
         if(Sinal()) {
            if(contaHedge) ColocaOrdemHedge(); else ColocaOrdem();
         }else {
            if(contaHedge) DeletaOrdemHedge(); else DeletaOrdem();
         }
      }
   }

   if(contaHedge) {
      if(PositionSelect(simbolo)) BreakevenHedge();
   }else {
      if(PositionSelect(simbolo)) { //Verifica se tem posição aberta para colocar alvos
         Breakeven();
         //Quando for trabalhar com mais de um ativo em conta netting, a linha abaixo deve ser alterada para analisar se as ordens abertas são do ativo atual.
         if(OrdersTotal() == 0 && PositionGetDouble(POSITION_VOLUME) == lote1+lote2) ColocaAlvo(); //Verifica se tem alvo e coloca caso não tenha.
      }else {
         DeletaAlvo(); //Gatilho de segurança. Se não há posição não deve haver alvos limit.
      }
   }
}

void OnDeinit(const int reason) {
   Comment("");
   if(contaHedge) DeletaOrdemHedge(); else DeletaOrdem();
   GlobalVariableSet("precoEntrada",precoEntrada);
   GlobalVariableSet("precoStop",precoStop);
   MessageBox("EA removido com sucesso!",NULL,MB_OK);
}

void IndBuffers() {
   maHandle_fast = iMA(simbolo, periodo, ma_period_fast, ma_shift_fast, ma_method_fast, applied_price_fast);
   maHandle_slow = iMA(simbolo, periodo, ma_period_slow, ma_shift_slow, ma_method_slow, applied_price_slow);
   stochHandle = iStochastic(simbolo, periodo, Kperiod, Dperiod, slowing, ma_method, price_field);

   CopyBuffer(maHandle_fast,0,0,3,maFast);
   CopyBuffer(maHandle_slow,0,0,3,maSlow);
   CopyBuffer(stochHandle,0,0,3,stoch);
}

bool Sinal() {
   sinal = 0;
   if(maFast[1] > maSlow[1]) {
      //Compra no Éden dos Traders
      if((rates[2].close < maFast[2] && rates[1].close > maFast[1]) || //Fechou abaixo e fechou acima da média rápida
         (rates[2].close > maFast[2] && rates[1].open > maFast[1] && rates[2].high > rates[1].high) || //Fechou acima na vela 2, com pullback e abertura no Éden dos Traders
         //Compra no Pullback
         (stoch[1] < sv)) //Sobrevenda
          sinal = 2;
   }else if(maFast[1] < maSlow[1]) {
      //Venda no Éden dos Traders
      if((rates[2].close > maFast[2] && rates[1].close < maFast[1]) || //Fechou acima e fechou abaixo da média rápida
         (rates[2].close < maFast[2] && rates[1].open < maFast[1] && rates[2].low < rates[1].low) || //Fechou abaixo na vela 2, com pullback e abertura no Éden dos Traders
         //Venda no Pullback
         (stoch[1] > sc)) //Sobrecompra
          sinal = -2;
   }
   Print("Sinal = "+IntegerToString(sinal));
   if(sinal == 2 || sinal == -2) return(true);
   return(false);
}

int InsideBar() {
   if(rates[2].high > rates[1].high && rates[2].low < rates[1].low) return(2);
   
   return(1);
}

bool NovoDia(int vela) {
   MqlDateTime ontem, hoje;
   
   TimeToStruct(rates[vela+1].time, ontem);
   TimeToStruct(rates[vela].time, hoje);
   if(ontem.day != hoje.day) return(true);
   return(false);
}

void ColocaOrdem() {
   int inside = InsideBar();
   
   if(OrdersTotal() == 1) DeletaOrdem(); //Puxada
   myRequest.volume = lote1+lote2;
   myRequest.action = TRADE_ACTION_PENDING;
   precoEntrada = (sinal == 2) ? rates[1].high : rates[1].low; //Necessário armazenar para usar como referência em Breakeven
   GlobalVariableSet("precoEntrada",precoEntrada); //Necessário armazenar para cálculo de Breakeven na reabertura do EA e manejo de posições manuais.

   myRequest.price = (sinal == 2) ? precoEntrada+tickSize : precoEntrada-tickSize;
   precoStop = (sinal == 2) ? rates[inside].low : rates[inside].high; //Necessário armazenar para setar stop real
   GlobalVariableSet("precoStop", precoStop); //Necessário armazenar para reabertura do EA ou manejo de posições manuais.

   StopFantasma((sinal == 2) ? precoStop-tickSize : precoStop+tickSize); //Desenha linha do Stop Fantasma
   myRequest.sl = (sinal == 2) ? precoStop-tickSize*stopInit : precoStop+tickSize*stopInit;

   myRequest.type = (sinal == 2) ? ((myRequest.price >= lastTick.ask) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_BUY_LIMIT)
    : ((myRequest.price <= lastTick.bid) ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_SELL_LIMIT);

   if(!OrderSend(myRequest,myResult)) Print("Envio de ordem de entrada falhou. Erro = ",GetLastError());
}

void ColocaOrdemHedge() {
   int inside = InsideBar();
   
   DeletaOrdemHedge(); //Puxada
   myRequest.action = TRADE_ACTION_PENDING;
   precoEntrada = (sinal == 2) ? rates[1].high : rates[1].low; //Necessário armazenar para usar como referência em Breakeven
   GlobalVariableSet("precoEntrada",precoEntrada); //Necessário armazenar para cálculo de Breakeven na reabertura do EA e manejo de posições manuais.

   myRequest.price = (sinal == 2) ? precoEntrada+tickSize+spread : precoEntrada-tickSize;
   precoStop = (sinal == 2) ? rates[inside].low : rates[inside].high; //Necessário armazenar para setar stop real
   GlobalVariableSet("precoStop", precoStop); //Necessário armazenar para reabertura do EA ou manejo de posições manuais.

   StopFantasma((sinal == 2) ? precoStop-tickSize : precoStop+tickSize); //Desenha linha do Stop Fantasma
   myRequest.sl = (sinal == 2) ? precoStop-tickSize*stopInit : precoStop+tickSize*stopInit;
   
   myRequest.type = (sinal == 2) ? ((myRequest.price >= lastTick.ask) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_BUY_LIMIT)
    : ((myRequest.price <= lastTick.bid) ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_SELL_LIMIT);

   myRequest.volume = lote1;
   double target = MathFloor(((rates[inside].high-rates[inside].low)*(alvo1/100.0))/tickSize)*tickSize;
   myRequest.tp = (sinal == 2) ? rates[1].high+target : rates[1].low-target;
   if(!OrderSend(myRequest,myResult)) Print("Envio de ordem de entrada falhou. Erro = ",GetLastError());

   myRequest.volume = lote2;
   target = MathFloor(((rates[inside].high-rates[inside].low)*(alvo2/100.0))/tickSize)*tickSize;
   myRequest.tp = (sinal == 2) ? rates[1].high+target : rates[1].low-target;
   if(!OrderSend(myRequest,myResult)) Print("Envio de ordem de entrada falhou. Erro = ",GetLastError());
}

void ColocaAlvo() {
   int inside = InsideBar();
   double target = MathFloor(((rates[inside].high-rates[inside].low)*(alvo1/100.0))/tickSize)*tickSize;
   long positionType = PositionGetInteger(POSITION_TYPE);
   
   myRequest.action = TRADE_ACTION_PENDING;
   myRequest.sl = 0;
   myRequest.type = (positionType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;
      
   myRequest.volume = lote1;
   myRequest.price = (positionType == POSITION_TYPE_BUY) ? rates[1].high+target : rates[1].low-target;

   Print("Colocando Alvo 1...");
   if(!OrderSend(myRequest,myResult)) Print("Envio de ordem, Alvo 1, falhou. Erro = ",GetLastError());
   
   if(alvo2 > 0) {
      target = MathFloor(((rates[inside].high-rates[inside].low)*(alvo2/100.0))/tickSize)*tickSize;
      myRequest.volume = lote2;
      myRequest.price = (positionType == POSITION_TYPE_BUY) ? rates[1].high+target : rates[1].low-target;

      Print("Colocando Alvo 2...");
      if(!OrderSend(myRequest,myResult)) Print("Envio de ordem, Alvo 2, falhou. Erro = ",GetLastError());
   }
}

void ColocaStop() {
   myRequest.action = TRADE_ACTION_SLTP;
   myRequest.sl = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? rates[1].low-tickSize : rates[1].high+tickSize;

   if(!OrderSend(myRequest,myResult)) Print("Inclusão de Stop no Trade falhou. Erro = ",GetLastError());
   ObjectDelete(0,"StopFantasma");
}

void ColocaStopHedge() {
   myRequest.action = TRADE_ACTION_SLTP;
   myRequest.sl = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? rates[1].low-tickSize : rates[1].high+tickSize+spread;
   int positionsTotal = PositionsTotal();

   for(int i = 0; i < positionsTotal; i++) {
      if(PositionGetSymbol(i) == simbolo) {
         if(!OrderSend(myRequest,myResult)) Print("Inclusão de Stop no Trade "+IntegerToString(i+1)+ ", falhou. Erro = ",GetLastError());
      }
   }

   ObjectDelete(0,"StopFantasma");
}

void Breakeven() {
   double stopLoss = PositionGetDouble(POSITION_SL);
   double target = MathFloor((MathAbs(precoEntrada-precoStop)*(breakEven/100.0))/tickSize)*tickSize;
   double entradaReal = PositionGetDouble(POSITION_PRICE_OPEN);

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
      if(stopLoss >= entradaReal) return;
      if(rates[0].high >= precoEntrada+target) myRequest.sl = entradaReal+breakEvenGap; else return;
   }else {
      if(stopLoss <= entradaReal) return;
      if(rates[0].low <= precoEntrada-target) myRequest.sl = entradaReal-breakEvenGap; else return;
   }
   myRequest.position = PositionGetTicket(0); //Precisa alterar isso se operar outros papéis simultâneos
   myRequest.action = TRADE_ACTION_SLTP;
   
   Print("Acionando Breakeven...");
   if(!OrderSend(myRequest,myResult)) Print("Envio de ordem Breakeven falhou. Erro = ",GetLastError());
}

void BreakevenHedge() {
   double stopLoss = PositionGetDouble(POSITION_SL);
   double target = MathFloor((MathAbs(precoEntrada-precoStop)*(breakEven/100.0))/tickSize)*tickSize;
   double entradaReal = PositionGetDouble(POSITION_PRICE_OPEN);

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
      if(stopLoss >= entradaReal) return; //BreakEven já posicionado.
      if(rates[0].high >= precoEntrada+target) myRequest.sl = entradaReal+breakEvenGap; else return; //Dúvida se uso precoEntrada ou entrada real
   }else {
      if(stopLoss <= entradaReal) return; //BreakEven já posicionado.
      if(rates[0].low <= precoEntrada-target) myRequest.sl = entradaReal-breakEvenGap; else return; //Dúvida se uso precoEntrada ou entrada real
   }

   myRequest.action = TRADE_ACTION_SLTP;
   int positionsTotal = PositionsTotal();
   for(int i = 0; i < positionsTotal; i++) {
      if(PositionGetSymbol(i) == simbolo) {
         myRequest.position = PositionGetTicket(i);
         myRequest.tp = PositionGetDouble(POSITION_TP);
         Print("Acionando Breakeven na posição restante...");
         if(!OrderSend(myRequest,myResult)) Print("Envio de ordem Breakeven falhou. Erro = ",GetLastError());
      }
   }
   ObjectDelete(0,"StopFantasma");
}

/*
void TrailingStop() {
   double stopLoss = PositionGetDouble(POSITION_SL);
   double tStop;

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
      tStop = MathFloor(pSar[1]/5)*5;
      if(tStop > stopLoss && tStop < rates[1].low && stopLoss >= precoEntrada) myRequest.sl = tStop; else return;
   }else {
      tStop = MathCeil(pSar[1]/5)*5;
      if(tStop < stopLoss && tStop > rates[1].high && stopLoss <= precoEntrada) myRequest.sl = tStop; else return;
   }
   myRequest.position = PositionGetTicket(0);
   myRequest.action = TRADE_ACTION_SLTP;
   
   Print("Acionando Trailing Stop...");
   if(!OrderSend(myRequest,myResult)) Print("Envio de ordem Trailing Stop falhou. Erro = ",GetLastError());

}
*/

void DeletaOrdem() {
   if(OrdersTotal() == 1) {
      myRequest.position = 0;
      myRequest.action = TRADE_ACTION_REMOVE;
      myRequest.order = OrderGetTicket(0);
      Print("Deletando Ordem...");
      if(!OrderSend(myRequest,myResult)) Print("Envio de ordem Deleção falhou. Erro = ",GetLastError());
   }
   precoEntrada = 0;
   precoStop = 0;
   ObjectDelete(0,"StopFantasma");
}

void DeletaOrdemHedge() {
   ulong ticket;
   myRequest.position = 0;
   myRequest.action = TRADE_ACTION_REMOVE;
   int ordersTotal=OrdersTotal();

   for(int i = ordersTotal-1; i >= 0; i--) {
      ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == simbolo) {
         myRequest.order = ticket;
         Print("Deletando ordem pendente na posição: "+IntegerToString(i));
         if(!OrderSend(myRequest,myResult)) Print("Tentativa de deletar a ordem Bilhete nº"+IntegerToString(ticket)+" falhou. Erro = ",GetLastError());
      }
   }

   if(!PositionSelect(simbolo)) {
      precoEntrada = 0;
      precoStop = 0;
   }
   ObjectDelete(0,"StopFantasma");
}

void DeletaAlvo() {
   int ordersTotal = OrdersTotal();
   ulong orderTicket;
   long orderType;

   for(int i = ordersTotal-1; i >= 0; i--) {
      orderTicket = OrderGetTicket(i);
      if(orderTicket > 0) {
         orderType = OrderGetInteger(ORDER_TYPE);
         if(orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_SELL_LIMIT) {
            myRequest.position = 0;
            myRequest.action = TRADE_ACTION_REMOVE;
            myRequest.order = orderTicket;
            Print("Deletando Alvo...");
            if(!OrderSend(myRequest,myResult)) Print("Envio de ordem Deleção falhou. Erro = ",GetLastError());
         }
      }
   }
}

void FechaPosicao() {
   ulong positionTicket = PositionGetTicket(0);
   
   if(positionTicket > 0) {
      long positionType = PositionGetInteger(POSITION_TYPE);
      
      myRequest.action = TRADE_ACTION_DEAL;
      myRequest.volume = PositionGetDouble(POSITION_VOLUME);
      myRequest.type = (positionType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      myRequest.price = (positionType == POSITION_TYPE_BUY) ? SymbolInfoDouble(simbolo,SYMBOL_BID) : SymbolInfoDouble(simbolo,SYMBOL_ASK);
      Print("Fechando posição...");
      if(!OrderSend(myRequest,myResult)) Print("Envio de ordem Fechamento falhou. Erro = ",GetLastError());
   }
   
}

bool BateuMeta() {
   double saldo = 0;
   datetime now=TimeCurrent();
   datetime today=(now/86400)*86400;

   if(meta == 0) return(false);
   
   if(HistorySelect(today,now)) {
      int historyDealsTotal = HistoryDealsTotal();
      for(int i = historyDealsTotal; i > 0; i--) {
         saldo += HistoryDealGetDouble(HistoryDealGetTicket(i-1),DEAL_PROFIT);
      }
   }else Print("Erro ao obter histórico de ordens e trades!");

   if(saldo > meta) {
      Comment("Meta diária alcançada! CARPE DIEM Guerreiro!");
      return(true);
   }

   return(false);
}

bool NovaVela(int bars) {
   static int lastBars = 0;
   
   if(bars>lastBars) {
      lastBars = bars;
      return(true);
   }
   return(false);
}

void StopFantasma(double sl) {
bool falhou = true;
   do {
      if(ObjectCreate(0,"StopFantasma",OBJ_HLINE,0,0,sl))
       if(ObjectFind(0,"StopFantasma") == 0)
        if(ObjectSetInteger(0,"StopFantasma",OBJPROP_STYLE,STYLE_DASH))
         if(ObjectGetInteger(0,"StopFantasma",OBJPROP_STYLE) == STYLE_DASH)
          if(ObjectSetInteger(0,"StopFantasma",OBJPROP_COLOR,clrRed))
           if(ObjectGetInteger(0,"StopFantasma",OBJPROP_COLOR) == clrRed) {
              ChartRedraw(0);
              falhou = false;
           }
   }while(falhou && !IsStopped());
}

bool TimeSession(int aStartHour,int aStartMinute,int aStopHour,int aStopMinute,datetime aTimeCur) {
//--- session start time
   int StartTime=3600*aStartHour+60*aStartMinute;
//--- session end time
   int StopTime=3600*aStopHour+60*aStopMinute;
//--- current time in seconds since the day start
   aTimeCur=aTimeCur%86400;
   if(StopTime<StartTime)
     {
      //--- going past midnight
      if(aTimeCur>=StartTime || aTimeCur<StopTime)
        {
         return(true);
        }
     }
   else
     {
      //--- within one day
      if(aTimeCur>=StartTime && aTimeCur<StopTime)
        {
         return(true);
        }
     }
   return(false);
}
//+------------------------------------------------------------------+
// Data: 11/06/2022
// Versão 1.00: ► Indicadores: 2EMA (8-80), Stocástico Lento 8-3-3
//              ► Opera rompimento de pullback dentro das médias e a favor delas em regiões Over
//              ► Fechou dentro, fechou fora da média rápida no Éden dos Traders ou 2x fora com pullback
// Data: 03/10/2022
// Versão 1.01: ► Detecção de modo Hege para Forex

// Versão 1.02: ► Virada de mão.