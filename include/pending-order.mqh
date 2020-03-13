//+------------------------------------------------------------------+
//|                                                pending-order.mqh |
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
//| Update Order List                                                |
//+------------------------------------------------------------------+
bool UpdatePendingOrderList()
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl=url+"/api/trading/accounts/"+(string)AccountID+"/orders";
   string headers= getHeaders(H_PUT);
   char data[];
   string str;

   parser = CreatePendingOrderListJson();
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
         PrintFormat("Error When Updating Order List: %s [ status code: %d ] ",parser["status"].ToStr(),parser["status_code"].ToInt());
         Print("AccountID: ",AccountID);
         Print("id_user: ",id_user);
         return(false);
        }
     }
   else
      Print("Failed to Deserialize");

   return(true);
  }
//+------------------------------------------------------------------+
//| Create currently pending order list                              |
//+------------------------------------------------------------------+
CJAVal CreatePendingOrderListJson()
  {
   double units;
   CJAVal parser(NULL,jtUNDEF);
   int j=0;

   parser["version"]                 = api_version;
   parser["delete_data_not_in_list"] = true;
   parser["date"]                    = dateToGMT(TimeCurrent());

   if(OrdersTotal()>0)
      for(int i=OrdersTotal()-1; i>=0; i--)
        {
         if(!OrderSelect(i,SELECT_BY_POS))
            continue;
         if(OrderType()<=OP_SELL)
            continue;
            
         units=OrderLots()*MarketInfo(OrderSymbol(), MODE_LOTSIZE);

         parser["data"][j++]=CreateOrderObjectJson((string)OrderTicket(),OrderSymbol(),units,OrderOpenPrice(),(ENUM_ORDER_TYPE)OrderType(),OrderStopLoss(),OrderTakeProfit(),OrderExpiration(),OrderOpenTime(),OrderCloseTime());
        }

   if(j==0)
      parser["data"] = "";

   return(parser);
  }

//+------------------------------------------------------------------+
//| Create Order JSON Data Object                                    |
//+------------------------------------------------------------------+
CJAVal CreateOrderObjectJson(const string order_id,const string symbol,const double lotsize,
                             const double open_price,const ENUM_ORDER_TYPE order_type,const double sl_level,
                             const double tp_level,const datetime expiry,const datetime open_time,const datetime closed_time)
  {
   CJAVal parser(NULL,jtUNDEF);

   string dir="SELL",type="LIMIT";
   if(order_type==OP_BUY|| order_type==OP_BUYSTOP|| order_type==OP_BUYLIMIT)
      dir="BUY";
   if(order_type== OP_BUYLIMIT|| order_type == OP_SELLLIMIT)
      type="LIMIT";
   else
      if(order_type==OP_BUYSTOP || order_type==OP_SELLSTOP)
         type="STOP";

   parser["order_id_from_provider"]       = order_id;
   parser["account_id"]                   = AccountID;
   parser["trade_id"]                     = "";
   parser["trade_id_from_provider"]       = order_id;
   parser["instrument_id_from_provider"]  = symbol;
   parser["units"]                        = lotsize;
   parser["currency"]                     = SymbolInfoString(symbol,SYMBOL_CURRENCY_BASE);
   parser["price"]                        = open_price;
   parser["execution_price"]              = open_price;
   parser["direction"]                    = dir;
   parser["stop_loss"]                    = sl_level;
   parser["take_profit"]                  = tp_level;
   parser["trailing_stop"]                = 0;
   parser["stop_loss_distance"]           = 0;
   parser["take_profit_distance"]         = 0;
   parser["trailing_stop_distance"]       = 0;
   parser["order_type"]                   = type;
   parser["status"]                       = order_type>OP_SELL?"PENDING":"FILLED";
   parser["expire_at"]                    = dateToGMT(expiry);
   parser["created_at_from_provider"]     = dateToGMT(open_time);
   parser["closed_at_from_provider"]      = dateToGMT(closed_time);

   return(parser);
  }
//+------------------------------------------------------------------+
