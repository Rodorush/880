//+------------------------------------------------------------------+
//|                                          DiagnosticoValidade.mq5 |
//|                                       Rodolfo Pereira de Andrade |
//+------------------------------------------------------------------+
#property copyright "Rodolfo Pereira de Andrade"
#property version   "1.00"
#property description "Prova quais combinações de tipo de ordem, validade e stop o"
#property description "servidor aceita. É EA e não script de propósito: a rejeição a"
#property description "investigar (retcode 10022) acontece dentro do Strategy Tester,"
#property description "e script não roda no tester."

// Por que existe: em 22/08/2026 o EA 880 levou TRADE_RETCODE_INVALID_EXPIRATION
// (10022) ao enviar um BUY STOP em WINV26 com ORDER_TIME_DAY, no tester. O
// Moving Average Channel usa ORDER_TIME_DAY no mesmo terminal e símbolo sem
// problema -- mas ele só manda ordem LIMIT, nunca STOP. Ou seja: nenhuma
// medição existente cobre o caso que falha.
//
// Este EA varre a matriz completa e diz, com retcode, o que o servidor aceita:
//
//     {BUY_STOP, SELL_STOP, BUY_LIMIT, SELL_LIMIT} x {GTC, DAY} x {com SL, sem SL}
//
// SEGURANÇA: recusa conta real sem override; usa magic próprio, isolado do EA
// 880; envia tudo LONGE do preço para não executar; e cancela cada ordem
// aceita imediatamente. Ao final se remove.

input int    InpDistanciaPontos  = 3000;  //Distância do preço em pontos (não deve executar)
input double InpVolume           = 0;     //Volume (0 = mínimo do símbolo)
input long   InpMagic            = 8809;  //Magic isolado do EA 880
input bool   InpPermiteContaReal = false; //Permitir rodar em conta REAL
input bool   InpTestaGTC         = false; //Repetir tudo com GTC (medido: WINV26 só aceita DAY)

string   gSimbolo;
double   gTick, gPonto, gVolume;
int      gDigitos, gNivelStops;
bool     gFeito = false;
ENUM_ORDER_TYPE_FILLING gFilling;

string   gResumo[];
int      gResumoN = 0;

//+------------------------------------------------------------------+
//| Decodificação das máscaras do símbolo                            |
//+------------------------------------------------------------------+
string DecodeValidade(const int m)
{
   string s = "";
   if((m & SYMBOL_EXPIRATION_GTC)           != 0) s += "GTC ";
   if((m & SYMBOL_EXPIRATION_DAY)           != 0) s += "DAY ";
   if((m & SYMBOL_EXPIRATION_SPECIFIED)     != 0) s += "SPECIFIED ";
   if((m & SYMBOL_EXPIRATION_SPECIFIED_DAY) != 0) s += "SPECIFIED_DAY ";
   return(s == "" ? "(nenhuma)" : s);
}

string DecodeFilling(const int m)
{
   string s = "";
   if((m & SYMBOL_FILLING_FOK) != 0) s += "FOK ";
   if((m & SYMBOL_FILLING_IOC) != 0) s += "IOC ";
   return(s == "" ? "(nenhum: só RETURN)" : s);
}

//| SYMBOL_ORDER_MODE diz se o símbolo sequer aceita ordem STOP.
string DecodeTiposDeOrdem(const int m)
{
   string s = "";
   if((m & SYMBOL_ORDER_MARKET)     != 0) s += "MARKET ";
   if((m & SYMBOL_ORDER_LIMIT)      != 0) s += "LIMIT ";
   if((m & SYMBOL_ORDER_STOP)       != 0) s += "STOP ";
   if((m & SYMBOL_ORDER_STOP_LIMIT) != 0) s += "STOP_LIMIT ";
   if((m & SYMBOL_ORDER_SL)         != 0) s += "SL ";
   if((m & SYMBOL_ORDER_TP)         != 0) s += "TP ";
   return(s == "" ? "(nenhum)" : s);
}

string DescreveRetcode(const uint rc)
{
   switch(rc)
   {
      case 0:     return("ZERO - struct nao preenchida");
      case 10008: return("PLACED - ACEITA");
      case 10009: return("DONE - ACEITA");
      case 10013: return("INVALID_REQUEST");
      case 10014: return("INVALID_VOLUME");
      case 10015: return("INVALID_PRICE");
      case 10016: return("INVALID_STOPS");
      case 10018: return("MARKET_CLOSED");
      case 10019: return("NO_MONEY");
      case 10022: return("INVALID_EXPIRATION  <<< o erro investigado");
      case 10030: return("INVALID_FILL");
      case 10031: return("CONNECTION");
   }
   return("outro");
}

//+------------------------------------------------------------------+
//| Preço bem longe, no lado correto para cada tipo de ordem         |
//+------------------------------------------------------------------+
double PrecoDe(const ENUM_ORDER_TYPE tipo, const MqlTick &t)
{
   double d = InpDistanciaPontos*gPonto;
   double p = 0;
   switch(tipo)
   {
      case ORDER_TYPE_BUY_STOP:        p = t.ask + d; break;  // gatilho acima
      case ORDER_TYPE_BUY_STOP_LIMIT:  p = t.ask + d; break;  // gatilho acima
      case ORDER_TYPE_SELL_LIMIT:      p = t.ask + d; break;  // acima do preço
      case ORDER_TYPE_SELL_STOP:       p = t.bid - d; break;  // gatilho abaixo
      case ORDER_TYPE_SELL_STOP_LIMIT: p = t.bid - d; break;  // gatilho abaixo
      case ORDER_TYPE_BUY_LIMIT:       p = t.bid - d; break;  // abaixo do preço
   }
   if(gTick > 0) p = MathRound(p/gTick)*gTick;
   return(NormalizeDouble(p,gDigitos));
}

bool EhCompra(const ENUM_ORDER_TYPE tipo)
{
   return(tipo == ORDER_TYPE_BUY_STOP || tipo == ORDER_TYPE_BUY_LIMIT ||
          tipo == ORDER_TYPE_BUY_STOP_LIMIT);
}

void Cancela(const ulong ticket)
{
   MqlTradeRequest req; ZeroMemory(req);
   MqlTradeResult  res; ZeroMemory(res);
   req.action = TRADE_ACTION_REMOVE;
   req.order  = ticket;
   req.magic  = InpMagic;
   // O retorno booleano não decide nada neste terminal (build 6116 devolve
   // false com erro 4756 mesmo tendo executado): o veredito é o retcode.
   bool ok = OrderSend(req,res);
   if(!ok && res.retcode == TRADE_RETCODE_DONE) { /* anomalia conhecida */ }
   if(res.retcode != TRADE_RETCODE_DONE && res.order == 0)
      PrintFormat("   ATENCAO: nao cancelei o ticket %I64u (retcode=%u). Cancele na mao.",
                  ticket, res.retcode);
}

//+------------------------------------------------------------------+
//| Uma combinação da matriz                                         |
//+------------------------------------------------------------------+
//| @param desvioStopLimit  ticks entre o gatilho e o preço limite resultante,
//|                         só usado nos tipos STOP_LIMIT. 0 = limite no gatilho.
void Prova(const ENUM_ORDER_TYPE tipo, const ENUM_ORDER_TYPE_TIME validade,
           const bool comSL, const int desvioStopLimit, const string rotulo,
           const MqlTick &t)
{
   double preco = PrecoDe(tipo,t);
   double d     = InpDistanciaPontos*gPonto;

   MqlTradeRequest req; ZeroMemory(req);
   MqlTradeResult  res; ZeroMemory(res);
   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = gSimbolo;
   req.volume       = gVolume;
   req.type         = tipo;
   req.price        = preco;
   req.type_time    = validade;
   req.type_filling = gFilling;
   req.magic        = InpMagic;
   req.comment      = "diag880";

   if(tipo == ORDER_TYPE_BUY_STOP_LIMIT || tipo == ORDER_TYPE_SELL_STOP_LIMIT)
   {
      // Ao atingir 'price' (gatilho), o servidor coloca uma ordem limite em
      // 'stoplimit'. Limite do lado marketável preenche na hora do disparo.
      double lim = EhCompra(tipo) ? preco + desvioStopLimit*gTick
                                  : preco - desvioStopLimit*gTick;
      req.stoplimit = NormalizeDouble(lim,gDigitos);
   }

   if(comSL)
   {
      double sl = EhCompra(tipo) ? preco - d : preco + d;
      if(gTick > 0) sl = MathRound(sl/gTick)*gTick;
      req.sl = NormalizeDouble(sl,gDigitos);
   }

   ResetLastError();
   bool ok  = OrderSend(req,res);
   int  err = GetLastError();

   string linha = StringFormat("%-22s %-15s %-7s %-14s -> ret=%-5s retcode=%-5u err=%-5d %s",
                               EnumToString(tipo), EnumToString(validade),
                               comSL ? "com SL" : "sem SL", rotulo,
                               ok ? "true" : "false", res.retcode, err,
                               DescreveRetcode(res.retcode));
   Print(linha);
   ArrayResize(gResumo,gResumoN+1);
   gResumo[gResumoN++] = linha;

   if(res.order != 0) Cancela(res.order);
}

//+------------------------------------------------------------------+
int OnInit()
{
   gSimbolo = _Symbol;

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !InpPermiteContaReal)
   {
      Print("Conta REAL e InpPermiteContaReal=false. Recusado.");
      return(INIT_FAILED);
   }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Print("Negociação não permitida (AutoTrading desligado?). Recusado.");
      return(INIT_FAILED);
   }

   gTick       = SymbolInfoDouble(gSimbolo,SYMBOL_TRADE_TICK_SIZE);
   gPonto      = SymbolInfoDouble(gSimbolo,SYMBOL_POINT);
   gDigitos    = (int)SymbolInfoInteger(gSimbolo,SYMBOL_DIGITS);
   gNivelStops = (int)SymbolInfoInteger(gSimbolo,SYMBOL_TRADE_STOPS_LEVEL);
   gVolume     = (InpVolume > 0) ? InpVolume : SymbolInfoDouble(gSimbolo,SYMBOL_VOLUME_MIN);

   int mFill = (int)SymbolInfoInteger(gSimbolo,SYMBOL_FILLING_MODE);
   int mExp  = (int)SymbolInfoInteger(gSimbolo,SYMBOL_EXPIRATION_MODE);
   int mOrd  = (int)SymbolInfoInteger(gSimbolo,SYMBOL_ORDER_MODE);

   gFilling = ORDER_FILLING_RETURN;
   if((mFill & SYMBOL_FILLING_FOK) != 0)      gFilling = ORDER_FILLING_FOK;
   else if((mFill & SYMBOL_FILLING_IOC) != 0) gFilling = ORDER_FILLING_IOC;

   Print("=====================================================================");
   Print("DIAGNOSTICO DE VALIDADE DE ORDEM  -  ", gSimbolo);
   Print("=====================================================================");
   PrintFormat("execucao          : %s",
               EnumToString((ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(gSimbolo,SYMBOL_TRADE_EXEMODE)));
   PrintFormat("tipos de ordem    : mascara=%d -> %s", mOrd,  DecodeTiposDeOrdem(mOrd));
   PrintFormat("validades         : mascara=%d -> %s", mExp,  DecodeValidade(mExp));
   PrintFormat("preenchimento     : mascara=%d -> %s (usando %s)",
               mFill, DecodeFilling(mFill), EnumToString(gFilling));
   PrintFormat("tick=%s point=%s digits=%d stops_level=%d volume=%s",
               DoubleToString(gTick,8), DoubleToString(gPonto,8),
               gDigitos, gNivelStops, DoubleToString(gVolume,2));
   Print("---------------------------------------------------------------------");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(gFeito) return;

   MqlTick t;
   if(!SymbolInfoTick(gSimbolo,t)) return;
   if(t.ask <= 0 || t.bid <= 0) return;
   gFeito = true;

   PrintFormat("cotacao no momento do teste: bid=%s ask=%s",
               DoubleToString(t.bid,gDigitos), DoubleToString(t.ask,gDigitos));
   Print("---------------------------------------------------------------------");

   ENUM_ORDER_TYPE tipos[] = {ORDER_TYPE_BUY_STOP,  ORDER_TYPE_SELL_STOP,
                              ORDER_TYPE_BUY_LIMIT, ORDER_TYPE_SELL_LIMIT};

   ENUM_ORDER_TYPE_TIME validades[2];
   int nValidades = 1;
   validades[0] = ORDER_TIME_DAY;
   if(InpTestaGTC) { validades[1] = ORDER_TIME_GTC; nValidades = 2; }

   for(int j = 0; j < nValidades; j++)
   {
      for(int i = 0; i < ArraySize(tipos); i++)
         for(int k = 0; k < 2; k++)
            Prova(tipos[i], validades[j], k == 1, 0, "-", t);

      // STOP_LIMIT: a ordem stop nativa da B3. O gatilho vai em 'price' e o
      // limite resultante em 'stoplimit'. Duas variantes, porque o servidor
      // pode exigir o limite de um lado específico do gatilho.
      ENUM_ORDER_TYPE tiposSL[] = {ORDER_TYPE_BUY_STOP_LIMIT, ORDER_TYPE_SELL_STOP_LIMIT};
      for(int i = 0; i < ArraySize(tiposSL); i++)
         for(int k = 0; k < 2; k++)
         {
            Prova(tiposSL[i], validades[j], k == 1, 0, "lim=gatilho",  t);
            Prova(tiposSL[i], validades[j], k == 1, 2, "lim=+2 ticks", t);
         }
   }

   Print("---------------------------------------------------------------------");
   Print("RESUMO - procure ACEITA nas linhas abaixo:");
   for(int i = 0; i < gResumoN; i++) Print("  ", gResumo[i]);
   Print("=====================================================================");
   Print("Ordens de teste foram canceladas. Confira que nao sobrou nenhuma com");
   PrintFormat("magic %I64d antes de seguir.", InpMagic);

   ExpertRemove();
}
