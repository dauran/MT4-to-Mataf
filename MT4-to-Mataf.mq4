//+-----------------------------------------------------------------------+
//|                                                      MT4-to-Mataf.mq4 |
//|       This software is licensed under the Apache License, Version 2.0 |
//|   which can be obtained at http://www.apache.org/licenses/LICENSE-2.0 |
//|                                                                       |
//|                             version 1.00 developed by Lakshan Perera: |
//|         https://www.upwork.com/o/profiles/users/_~0117e7a3d2ba0ba25e/ |
//|                                                                       |
//|                                             Documentation of the API: |
//| https://documenter.getpostman.com/view/425042/S17kzr7Y?version=latest |
//|                                                                       |
//|                            Create an account on https://www.mataf.net |
//|                  use your credentials (email+password) to use this EA |
//|                                                                       |
//+-----------------------------------------------------------------------+
#property copyright "Mataf.net"
#property link      "https://www.mataf.net"
#property version   "1.01"
#property strict
#include "JAson.mqh"
#include <WinUser32.mqh>

#import "user32.dll"
int GetAncestor(int hWnd,int gaFlags);
int SetForegroundWindow(int hWnd);
int SendMessageA(int hWnd,int Msg,int wParam,int lParam);
#import

//--- input parameters
input int         updateFrequency = 5;                        // Update Interval(in seconds)
input string      url="https://www.mataf.io";                 // URL
input string      email="";                                   // Email
input string      password="";                                // Password
input int         api_call_timeout=60000;                     // Time out
input string      token_file_name="MT4APISettings.txt";       // Settings File Name
input string      AccountAlias="Test Account";

string token="";
int id_user;
int api_version=1;
int AccountID;
string settings_file="";
CJAVal settingsFileParser;
bool previous_finished=true;
//+------------------------------------------------------------------+
//| File Type                                                        |
//+------------------------------------------------------------------+
enum ENUM_FILE_TYPE
  {
   TOKEN,
   USER_ID,
   ACCOUNT_ID
  };
bool connected=false;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create timer
   EventSetTimer(updateFrequency);
   if(!connected)
      return(ApiOnInit());
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
   EventKillTimer();

  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {

  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
//---
   if(!MQLInfoInteger(MQL_TESTER) && previous_finished)
     {
      OnTickSimulated();
     }
  }
//+------------------------------------------------------------------+
//| Connect To the API                                               |
//+------------------------------------------------------------------+
int ApiOnInit()
  {
   Comment("Gettting the token...");
   GetToken();

   Sleep(300);
   Comment("Creating an account...");
   if(!CreateAccount())
     {
      //---trying again with a fresh token
      GetToken();
      if(!CreateAccount())
        {
         Comment("Account Creation Failed!");
         return(INIT_FAILED);
        }
     }
   else
      Comment("Account created!...");
   Sleep(500);

//Alert("Connected!");
   Comment("");
   UpdateTradesList(true);
   UpdateOrderList();
//OnTickSimulated();
   connected=true;
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Send request at given frequency                                  |
//+------------------------------------------------------------------+
void OnTickSimulated()
  {
   previous_finished=false;
   CreateAccount(false);
   if(!UpdateOrderList())
     {
      Sleep(10);
      UpdateOrderList();
     }
   if(!UpdateTradesList())
     {
      Sleep(10);
      UpdateTradesList();
     }
   previous_finished=true;
  }
//+------------------------------------------------------------------+
//| Save token, id_user and AccountID onto the settings file         |
//+------------------------------------------------------------------+
void SaveSettings()
  {
   int handle=FileOpen(token_file_name,FILE_WRITE|FILE_TXT);
   FileWriteString(handle,settings_file);
   FileFlush(handle);
   FileClose(handle);
   Print("Token and id_user saved to file");
  }
//+------------------------------------------------------------------+
//| Get new token                                                    |
//+------------------------------------------------------------------+
bool GetToken()
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl = url+"/api/user/login";
   string headers = StringFormat("Content-Type: application/json\r\n X-Mataf-api-version: %d\r\n",api_version);
   string str;
   char data[];

   parser["email"]=email;
   parser["password"]=password;
   parser.Serialize(str);

   ArrayResize(data,StringToCharArray(str,data,0,-1,CP_UTF8)-1);
   int result=WebRequest("POST",fullUrl,headers,api_call_timeout,data,data,headers);

   if(parser.Deserialize(data))
     {
      token=parser["data"]["token"].ToStr();
     }
   else
     {
      Print("Failed to get Token from API");
      return(false);
     }

   id_user=(int)parser["data"]["id_user"].ToInt();

//Print("New Token stored for id_user=",id_user);

   settingsFileParser["token"]=token;
   settingsFileParser["id_user"]=id_user;

   settings_file=settingsFileParser.Serialize();
   SaveSettings();

   return(true);
  }
//+------------------------------------------------------------------+
//| Refresh the token                                                |
//+------------------------------------------------------------------+
bool RefreshToken()
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl=url+"/api/user/refreshToken";
   string headers= StringFormat("Content-Type: application/json\r\n X-Mataf-token: %s\r\n X-Mataf-id: %d\r\n X-Mataf-api-version: %d",token,id_user,api_version);

   char data[];
   string str="";

   parser["id_user"]=id_user;
   parser["token"]=token;
   parser.Serialize(str);

   ArrayResize(data,StringToCharArray(str,data,0,-1,CP_UTF8)-1);
   int result=WebRequest("POST",fullUrl,headers,api_call_timeout,data,data,headers);
   Print("Result is "+(string)result+": "+(string)GetLastError());

   if(parser.Deserialize(data))
     {
      token=parser["data"]["token"].ToStr();
     }
   else
     {
      Print("Failed to Deserialize");
      return(false);
     }

   id_user=(int)parser["data"]["id_user"].ToInt();

   Print("Token: "+token);
   Print("id_user: ",id_user);

   settingsFileParser["token"]=token;
   settingsFileParser["id_user"]=id_user;

   settings_file=settingsFileParser.Serialize();
   SaveSettings();

   return(true);
  }
//+------------------------------------------------------------------+
//| Create new account/update existing                               |
//+------------------------------------------------------------------+
bool CreateAccount(const bool firstRun=true)
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl=url+"/api/trading/accounts";
   string headers= StringFormat("Content-Type: application/json\r\n X-Mataf-token: %s\r\n X-Mataf-id: %d\r\n X-Mataf-api-version: %d",token,id_user,api_version);

   char data[];
   string str="";
   string created_time="";
   int hwindow=GetAncestor(WindowHandle(Symbol(),Period()),2);
   if(hwindow!=0)
     {
      SetForegroundWindow(hwindow); //active the terminal (the terminal most be the active window)
      Sleep(100);
      SendMessageA(hwindow,WM_COMMAND,33058,0);
     }

   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
     {
      Sleep(500);
      if(!OrderSelect(0,SELECT_BY_POS,MODE_HISTORY))
         continue;
      if(OrderType()!=6)
         continue;
      created_time=TimeToString(OrderCloseTime(),TIME_SECONDS|TIME_DATE);

      break;
     }

   double total_deposits=0,total_withdraw=0;
   CJAVal acountdepositsObject(NULL,jtUNDEF);

   int j=0;
   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
         continue;
      if(OrderType()!=6)
         continue;
      if(OrderProfit()>0)
        {
         total_deposits           += OrderProfit();
         acountdepositsObject[j++] = CreateAccountTransactionJson("FUNDING",OrderProfit(),OrderOpenTime(),OrderTicket(),OrderComment());
        }
      else
        {
         total_withdraw           += MathAbs(OrderProfit());
         acountdepositsObject[j++] = CreateAccountTransactionJson("WITHDRAW",OrderProfit(),OrderOpenTime(),OrderTicket(),OrderComment());
        }
     }

   parser["version"]                          = api_version;
   parser["data"]["account_id_from_provider"] = (string)AccountNumber();
   parser["data"]["provider_name"]            = AccountCompany();
   parser["data"]["source_name"]              = "MT4";
   parser["data"]["user_id_from_provider"]    = (string)AccountNumber();
   parser["data"]["account_alias"]            = AccountAlias;
   parser["data"]["account_name"]             = AccountName();
   parser["data"]["currency"]                 = AccountCurrency();
   parser["data"]["is_live"]                  = !IsDemo();
   parser["data"]["is_active"]                = true;
   parser["data"]["balance"]                  = (float)AccountBalance();
   parser["data"]["profit_loss"]              = AccountBalance()-(total_deposits-total_withdraw);
   parser["data"]["open_profit_loss"]         = AccountProfit();
   parser["data"]["funds"]["deposit"]         = total_deposits;
   parser["data"]["funds"]["withdraw"]        = -1*total_withdraw;
   parser["data"]["history"]                  = acountdepositsObject;
   parser["data"]["created_at_from_provider"] = created_time;

   parser.Serialize(str);

   ArrayResize(data,StringToCharArray(str,data,0,-1,CP_UTF8)-1);
   int result=WebRequest("POST",fullUrl,headers,api_call_timeout,data,data,headers);

   if(parser.Deserialize(data))
     {
      if(parser["is_error"].ToBool())
        {
         PrintFormat("Error When Creating Account: %s [ status code: %d ] ",parser["status"].ToStr(),parser["status_code"].ToInt());
         return(false);
        }
      else
        {
         AccountID=(int)parser["data"]["id"].ToInt();
         if(firstRun)
            PrintFormat("Account Created successfully, Account ID: %d",AccountID);
        }
     }
   else
     {
      Print("Failed to Deserialize");
      return(false);
     }

   settingsFileParser["AccountID"]=AccountID;
   settings_file=settingsFileParser.Serialize();
   if(firstRun)
      SaveSettings();

   return(true);
  }
//+------------------------------------------------------------------+
//| Update Order List                                                |
//+------------------------------------------------------------------+
bool UpdateOrderList()
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl=url+"/api/trading/accounts/"+(string)AccountID+"/orders";
   string headers= StringFormat("Content-Type: application/json\r\n X-Mataf-token: %s\r\n X-Mataf-id: %d\r\n X-Mataf-api-version: %d\r\n X-HTTP-Method-Override: PUT",token,id_user,api_version);
   char data[];
   string str;

   parser = CreateOpenedOrderListJson();
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
//| Update Trades List                                                |
//+------------------------------------------------------------------+
bool UpdateTradesList(const bool firstRun=false)
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl=url+"/api/trading/accounts/"+(string)AccountID+"/trades";
   string headers= StringFormat("Content-Type: application/json\r\n X-Mataf-token: %s\r\n X-Mataf-id: %d\r\n X-Mataf-api-version: %d\r\n X-HTTP-Method-Override: PUT",token,id_user,api_version);

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
//| Get the current time stamp                                       |
//+------------------------------------------------------------------+
datetime GetLastActiveTimeStamp()
  {
   return(0);
  }
//+------------------------------------------------------------------+
//| Create Withdrawing and Depositing JSON Data Object               |
//+------------------------------------------------------------------+
CJAVal CreateAccountTransactionJson(const string method,const double amount,const datetime time,const int id,const string comment)
  {
   CJAVal parser(NULL,jtUNDEF);
   parser["type"]=method;
   parser["amount"]=amount;
   parser["time"]=TimeToString(time,TIME_SECONDS|TIME_DATE);
   parser["transaction_id_from_provider"]=(string)id;
   parser["comment"]=comment;

   return(parser);
  }
//+------------------------------------------------------------------+
//| Create Withdrawing and Depositing JSON Data Object               |
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

   parser["order_id_from_provider"]=order_id;
   parser["account_id"]=AccountID;
   parser["trade_id"]="";
   parser["trade_id_from_provider"]=order_id;
   parser["instrument_id_from_provider"]=symbol;
   parser["units"]=lotsize;
   parser["currency"]=symbol;
   parser["price"]=open_price;
   parser["execution_price"]=open_price;
   parser["direction"]=dir;
   parser["stop_loss"]=sl_level;
   parser["take_profit"]=tp_level;
   parser["trailing_stop"]=0;
   parser["stop_loss_distance"]=0;
   parser["take_profit_distance"]=0;
   parser["trailing_stop_distance"]=0;
   parser["order_type"]=type;
   parser["status"]=order_type>OP_SELL?"PENDING":"FILLED";
   parser["expire_at"]=expiry>0?TimeToString(expiry,TIME_SECONDS|TIME_DATE):(string)0;
   parser["created_at_from_provider"]=open_time>0?TimeToString(open_time,TIME_SECONDS|TIME_DATE):(string)0;
   parser["closed_at_from_provider"]=closed_time>0?TimeToString(closed_time,TIME_SECONDS|TIME_DATE):(string)0;

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
   CJAVal parser(NULL,jtUNDEF);
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

   parser["trade_id_from_provider"]       = order_id;
   parser["account_id"]                   = AccountID;
   parser["instrument_id_from_provider"]  = symbol;
   parser["direction"]                    = dir;
   parser["type"]                         = order_type<=OP_SELL?"MARKET":type;
   parser["units"]                        = lotsize;
   parser["currency"]                     = StringSubstr(symbol,3,3);
   parser["open_price"]                   = open_price;
   parser["closed_price"]                 = closed_time>0?closed_price:0;
   parser["profit_loss"]                  = closed_time>0?PnL:0.0;
   parser["open_profit_loss"]             = closed_time>0?0:PnL;
   parser["rollover"]                     = rollover;
   parser["commission"]                   = commission;
   parser["other_fees"]                   = other_fees;
   parser["spread_cost"]                  = spread_cost;
   parser["status"]                       = closed_time>0?(order_type>OP_SELL?"CANCELLED":"CLOSED"):"OPEN";
   parser["balance_at_opening"]           = AccountBalance()-PnL;
   parser["stop_loss"]                    = sl_level;
   parser["take_profit"]                  = tp_level;
   parser["trailing_stop"]                = 0;
   parser["stop_loss_distance"]           = 0;
   parser["take_profit_distance"]         = 0;
   parser["trailing_stop_distance"]       = 0;
   parser["created_at_from_provider"]     = open_time>0?TimeToString(open_time,TIME_SECONDS|TIME_DATE):(string)0;
   parser["closed_at_from_provider"]      = closed_time>0?TimeToString(closed_time,TIME_SECONDS|TIME_DATE):(string)0;

   return(parser);
  }
//+------------------------------------------------------------------+
//| Create currently opened order list                               |
//+------------------------------------------------------------------+
CJAVal CreateOpenedOrderListJson()
  {
   double units;
   CJAVal parser(NULL,jtUNDEF);
   int j=0;

   parser["version"]                 = api_version;
   parser["delete_data_not_in_list"] = true;

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
//| Create currently opened and closed trade list                    |
//+------------------------------------------------------------------+
CJAVal CreateTradesListJson(const bool firstRun)
  {
   double units;
   CJAVal parser(NULL,jtUNDEF);

   parser["version"]                 = api_version;
   parser["delete_data_not_in_list"] = firstRun;

   datetime today = StringToTime(TimeToString(TimeCurrent(),TIME_DATE|TIME_DATE));
   int j = 0;

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

   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
         continue;
      if(OrderSymbol()=="" || OrderSymbol()==NULL || (!firstRun && OrderCloseTime()<today))
         continue;

      units               = OrderLots()*MarketInfo(OrderSymbol(), MODE_LOTSIZE);
      parser["data"][j++] = CreateTradeObjectJson((string)OrderTicket(),OrderSymbol(),units,OrderOpenPrice(),OrderClosePrice(),OrderProfit(),(ENUM_ORDER_TYPE)OrderType(),OrderStopLoss(),OrderTakeProfit(),
                            OrderOpenTime(),OrderCloseTime(),OrderCommission(),OrderSwap(),0);
     }

  if(j==0)
      parser["data"] = "";

   return(parser);
  }
//+------------------------------------------------------------------+
