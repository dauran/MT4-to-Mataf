//+------------------------------------------------------------------+
//|                                                       trades.mqh |
//|                                                    Arnaud Jeulin |
//|                                            https://www.mataf.net |
//+------------------------------------------------------------------+
#property copyright "Arnaud Jeulin"
#property link      "https://www.mataf.net"
#property strict
//+------------------------------------------------------------------+
//| imports                                                          |
//+------------------------------------------------------------------+
#include "JAson.mqh"
//+------------------------------------------------------------------+
//| Update Trades List                                                |
//+------------------------------------------------------------------+
bool UpdateTradesList(const bool firstRun=false)
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl=url+"/api/trading/accounts/"+(string)AccountID+"/trades";
   string headers= getHeaders(H_PUT);

   char data[];
   string str;

   parser = CreateTradesListJson(firstRun);

   if(!firstRun && parser["data"].Size()==0)
      return(true);

   parser.Serialize(str);

   ArrayResize(data,StringToCharArray(str,data,0,-1,CP_UTF8)-1);
   int result=WebRequest("POST",fullUrl,headers,api_call_timeout,data,data,headers);

   int error= GetLastError();
   if(error!=ERR_NO_MQLERROR || result!=200)
      Print("Result is "+(string)result+": "+(string)error);
   if(parser.Deserialize(data))
     {
      if(parser["is_error"].ToBool())
        {
         PrintFormat("Error When Updating Trades List: %s [ status code: %d ] ",parser["status"].ToStr(),parser["status_code"].ToInt());
         Print("AccountID: ",AccountID);
         Print("id_user: ",id_user);
         return(false);
        }
      else
        {
         //Print("Trades list updated successfully");
        }
     }
   else
      Print("Failed to Deserialize @ UpdateTradeList()");

   return(true);
  }
//+------------------------------------------------------------------+
//| Create currently opened and closed trade list                    |
//+------------------------------------------------------------------+
CJAVal CreateTradesListJson(const bool firstRun)
  {
   double units;
   CJAVal parser(NULL,jtUNDEF);

   parser["version"]                 = api_version;
   parser["delete_data_not_in_list"] = firstRun;
   parser["date"]                    = dateToGMT(TimeCurrent());

   datetime yesterday = TimeCurrent() - (24*60*60);
   int j = 0;

//Open Positions
   Comment("List open positions!");
   if(OrdersTotal()>0)
     {
      for(int i=OrdersTotal()-1; i>=0; i--)
        {
         if(!OrderSelect(i,SELECT_BY_POS))
            continue;
         if(OrderType()>OP_SELL)
            continue;

         units               = OrderLots()*MarketInfo(OrderSymbol(), MODE_LOTSIZE);
         parser["data"][j++] = CreateTradeObjectJson((string)OrderTicket(),OrderSymbol(),units,OrderOpenPrice(),OrderClosePrice(),OrderProfit(),(ENUM_ORDER_TYPE)OrderType(),OrderStopLoss(),OrderTakeProfit(),
                               OrderOpenTime(),OrderCloseTime(),OrderCommission(),OrderSwap(),0);
        }
     }
//Closed Positions
   if(OrdersHistoryTotal()>0)
     {
      for(int i=OrdersHistoryTotal()-1; i>=0; i--)
        {
         if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
            continue;
         if(OrderSymbol()=="" || OrderSymbol()==NULL || (!firstRun && OrderCloseTime()<yesterday))
            continue;

         units               = OrderLots()*MarketInfo(OrderSymbol(), MODE_LOTSIZE);
         parser["data"][j++] = CreateTradeObjectJson((string)OrderTicket(),OrderSymbol(),units,OrderOpenPrice(),OrderClosePrice(),OrderProfit(),(ENUM_ORDER_TYPE)OrderType(),OrderStopLoss(),OrderTakeProfit(),
                               OrderOpenTime(),OrderCloseTime(),OrderCommission(),OrderSwap(),0);
        }
     }

   if(j==0)
      parser["data"] = "";

   return(parser);
  }

//+------------------------------------------------------------------+
//| Create a trade object in JSON                                    |
//+------------------------------------------------------------------+
CJAVal CreateTradeObjectJson(const string order_id,const string symbol,const double lotsize,
                             const double open_price,const double closed_price,const double PnL,const ENUM_ORDER_TYPE order_type,const double sl_level,
                             const double tp_level,const datetime open_time,const datetime closed_time,const double commission,const double rollover,const double other_fees
                            )
  {
   CJAVal tradeObject(NULL,jtUNDEF);
   double spread_cost = SymbolInfoInteger(symbol,SYMBOL_SPREAD)*Point*SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE)*lotsize;

   string dir = "SELL";
   if(order_type == OP_BUY || order_type == OP_BUYSTOP || order_type == OP_BUYLIMIT)
      dir = "BUY";

   string type = "";
   if(order_type==OP_BUYLIMIT || order_type==OP_SELLLIMIT)
      type = "LIMIT";
   else
      if(order_type==OP_BUYSTOP || order_type==OP_SELLSTOP)
         type = "STOP";

   tradeObject["trade_id_from_provider"]       = order_id;
   tradeObject["account_id"]                   = AccountID;
   tradeObject["instrument_id_from_provider"]  = symbol;
   tradeObject["direction"]                    = dir;
   tradeObject["type"]                         = order_type<=OP_SELL?"MARKET":type;
   tradeObject["units"]                        = lotsize;
   tradeObject["currency"]                     = SymbolInfoString(symbol,SYMBOL_CURRENCY_BASE);
   tradeObject["open_price"]                   = open_price;
   tradeObject["closed_price"]                 = closed_time>0 ? closed_price : 0;
   tradeObject["profit_loss"]                  = closed_time>0 ? PnL : 0.0;
   tradeObject["open_profit_loss"]             = closed_time>0 ? 0 : PnL;
   tradeObject["rollover"]                     = rollover;
   tradeObject["commission"]                   = commission;
   tradeObject["other_fees"]                   = other_fees;
   tradeObject["spread_cost"]                  = spread_cost;
   tradeObject["status"]                       = closed_time>0?(order_type>OP_SELL?"CANCELLED":"CLOSED"):"OPEN";
   tradeObject["balance_at_opening"]           = balanceSearch(dateToGMT(open_time)); //AccountBalance()-PnL;
   tradeObject["stop_loss"]                    = sl_level;
   tradeObject["take_profit"]                  = tp_level;
   tradeObject["trailing_stop"]                = 0;
   tradeObject["stop_loss_distance"]           = 0;
   tradeObject["take_profit_distance"]         = 0;
   tradeObject["trailing_stop_distance"]       = 0;
   tradeObject["created_at_from_provider"]     = dateToGMT(open_time);
   tradeObject["closed_at_from_provider"]      = dateToGMT(closed_time);
   tradeObject["current_time"]                 = dateToGMT(TimeCurrent());

   return(tradeObject);
  }
//+------------------------------------------------------------------+
