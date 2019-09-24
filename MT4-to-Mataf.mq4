//+-----------------------------------------------------------------------+
//|                                                      MT4-to-Mataf.mq4 |
//|       This software is licensed under the Apache License, Version 2.0 |
//|   which can be obtained at http://www.apache.org/licenses/LICENSE-2.0 |
//|                                                                       |
//|                                          Developed by Lakshan Perera: |
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
#property version   "1.00"
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
   LoadSettings();

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
   else Comment("Account created!...");
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
//| Update Historical Orders Once Per Day                            |
//+------------------------------------------------------------------+
string UpdateCacheHistory(const datetime today)
  {
   double units;
   int x=0;
   static string jsonH="";

   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderCloseTime()>=today) break;
      if(OrderType()>OP_SELL) continue;

      if(x>0)jsonH+=",";
      units=OrderLots()*MarketInfo(OrderSymbol(),MODE_LOTSIZE);
      jsonH+=CreateTradeObjectJson((string)OrderTicket(),OrderSymbol(),units,OrderOpenPrice(),OrderClosePrice(),OrderProfit(),(ENUM_ORDER_TYPE)OrderType(),OrderStopLoss(),OrderTakeProfit(),
                                   OrderOpenTime(),OrderCloseTime(),OrderCommission(),OrderSwap(),0);
      x++;
     }
   return(jsonH);
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
//| Load settings: Token, id_user and AccountID from file            |
//+------------------------------------------------------------------+
void LoadSettings()
  {
   if(FileIsExist(token_file_name))
     {
      int handle=FileOpen(token_file_name,FILE_READ|FILE_TXT);
      settings_file=FileReadString(handle);
      FileClose(handle);
      Print("Settings file is loaded!");

      if(settingsFileParser.Deserialize(settings_file))
        {
         token=settingsFileParser["token"].ToStr();
         id_user=(int)settingsFileParser["id_user"].ToInt();
         AccountID=(int)settingsFileParser["AccountID"].ToInt();

         if(AccountID<=0 || id_user<=0 || token=="") GetToken();
        }
     }
   else GetToken();
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
   Print("Settings saved to file");
  }
//+------------------------------------------------------------------+
//| Get new token                                                    |
//+------------------------------------------------------------------+
bool GetToken()
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl = url+"/api/user/login";
   string headers = "Content-Type: application/json\r\n X-Mataf-api-version: 1\r\n";
   char data[];
   string str="{"
              +GetLine("email",email)
              +GetLine("password",password,true)
              +"\r\n}";

   StringToCharArray(str,data,0,StringLen(str),CP_UTF8);
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

   Print("New Token: "+token);
   Print("id_user: ",id_user);

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
   string headers= StringFormat("Content-Type: application/json\r\n X-Mataf-token: %s\r\n X-Mataf-id: %d\r\n X-Mataf-api-version: 1",token,id_user);

   char data[];
   string str="";

   parser["id_user"]=id_user;
   parser["token"]=token;
   parser.Serialize(str);

   StringToCharArray(str,data,0,StringLen(str),CP_UTF8);
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
   string headers= StringFormat("Content-Type: application/json\r\n X-Mataf-token: %s\r\n X-Mataf-id: %d\r\n X-Mataf-api-version: 1",token,id_user);

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

   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
     {
      Sleep(500);
      if(!OrderSelect(0,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderType()!=6) continue;
      created_time=TimeToString(OrderCloseTime(),TIME_SECONDS|TIME_DATE);

      break;
     }

   double total_deposits=0,total_withdraw=0;
   string acountdepositsObject="";

   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderType()!=6) continue;
      if(OrderProfit()>0)
        {
         total_deposits+=OrderProfit();
         acountdepositsObject+=CreateAccountTransactionJson("FUNDING",OrderProfit(),OrderOpenTime(),OrderTicket(),OrderComment());
        }
      else
        {
         total_withdraw+=MathAbs(OrderProfit());
         acountdepositsObject+=CreateAccountTransactionJson("WITHDRAW",OrderProfit(),OrderOpenTime(),OrderTicket(),OrderComment());
        }
      if(i!=0)acountdepositsObject+=",";
     }

   string AccountJson="{"
                      +GetLine("account_id_from_provider",(string)AccountNumber())
                      +GetLine("provider_name",AccountCompany())
                      +GetLine("source_name","MT4")
                      +GetLine("user_id_from_provider",(string)AccountNumber())
                      +GetLine("account_alias",AccountAlias)
                      +GetLine("account_name",AccountName())
                      +GetLine("currency",AccountCurrency())
                      +GetLine("is_live",!IsDemo())
                      +GetLine("is_active",true)
                      +GetLine("balance",(float)AccountBalance())
                      +GetLine("profit_loss",AccountBalance()-(total_deposits-total_withdraw))
                      +GetLine("open_profit_loss",AccountProfit())
                      +"\"funds\":"
                      +"{"
                      +GetLine("deposit",total_deposits)
                      +GetLine("withdraw",-1*total_withdraw)
                      +"\"history\":"
                      +"["
                      +acountdepositsObject
                      +"]"
                      +"},"
                      //+GetLine("rollover",0)
                      //+GetLine("commission",0)
                      //+GetLine("other_fees",0)
                      +GetLine("created_at_from_provider",created_time,true)
                      +"}";

   str="{"
       +GetLine("version",1)
       +"\"data\":"+AccountJson
       +"}";

//--- save the json to a file
   if(firstRun)
     {
      int handle=FileOpen(__FUNCTION__+".json",FILE_WRITE|FILE_TXT|FILE_SHARE_READ);
      FileWriteString(handle,str);
      FileClose(handle);
      //     return(true);
     }
//--- end saving

   StringToCharArray(str,data,0,StringLen(str),CP_UTF8);
   int result=WebRequest("POST",fullUrl,headers,api_call_timeout,data,data,headers);
   if(firstRun)Print("Result is "+(string)result+": "+(string)GetLastError());
   if(result!=200)return(false);

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
         if(firstRun)PrintFormat("Account Created successfully, Account ID: %d",AccountID);
        }
     }
   else
     {
      Print("Failed to Deserialize");
      return(false);
     }

   settingsFileParser["AccountID"]=AccountID;
   settings_file=settingsFileParser.Serialize();
   if(firstRun)SaveSettings();

   return(true);
  }
//+------------------------------------------------------------------+
//| Update Order List                                                |
//+------------------------------------------------------------------+
bool UpdateOrderList()
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl=url+"/api/trading/accounts/"+(string)AccountID+"/orders";
   string headers= StringFormat("Content-Type: application/json\r\n X-Mataf-token: %s\r\n X-Mataf-id: %d\r\n X-Mataf-api-version: 1\r\n X-HTTP-Method-Override: PUT",token,id_user);
   char data[];
   string str=CreateOpenedOrderListJson();
   if(str=="" || str==NULL) return(true);
   StringToCharArray(str,data,0,StringLen(str),CP_UTF8);

   int result=WebRequest("POST",fullUrl,headers,api_call_timeout,data,data,headers);

   int error= GetLastError();
   if(error!=ERR_NO_MQLERROR || result!=200)
      Print("Result is "+(string)result+": "+(string)error);

   if(parser.Deserialize(data))
     {
      if(parser["is_error"].ToBool())
        {
         PrintFormat("Error When Updating Order List: %s [ status code: %d ] ",parser["status"].ToStr(),parser["status_code"].ToInt());
         Print("Token: ",token);
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
bool UpdateTradesList(const bool firsRun=false)
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl=url+"/api/trading/accounts/"+(string)AccountID+"/trades";
   string headers= StringFormat("Content-Type: application/json\r\n X-Mataf-token: %s\r\n X-Mataf-id: %d\r\n X-Mataf-api-version: 1\r\n X-HTTP-Method-Override: PUT",token,id_user);
//Print("headers: ",headers);
   char data[];
   string str=CreateTradesListJson(firsRun);

   if(str=="" || str==NULL) return(true);
//--- save the json to a file
   if(firsRun)
     {
      int handle=FileOpen("UpdateTradesListOnFirstRun.json",FILE_WRITE|FILE_TXT|FILE_SHARE_READ);
      FileWriteString(handle,str);
      FileClose(handle);
      //     return(true);
     }
//--- end saving

   StringToCharArray(str,data,0,StringLen(str),CP_UTF8);

   int result=WebRequest("POST",fullUrl,headers,api_call_timeout,data,data,headers);

   int error= GetLastError();
   if(error!=ERR_NO_MQLERROR || result!=200)
      Print("Result is "+(string)result+": "+(string)error);
   if(parser.Deserialize(data))
     {
      if(parser["is_error"].ToBool())
        {
         PrintFormat("Error When Updating Trades List: %s [ status code: %d ] ",parser["status"].ToStr(),parser["status_code"].ToInt());
         Print("Token: ",token);
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
//| Easier JSON Parser by line (key:value pair)                      |
//+------------------------------------------------------------------+
template<typename T>
string GetLine(const string key,const T value,const bool lastline=false)
  {
   if(typename(T)=="string")return(lastline?"\t\r\n\""+key+"\":"+"\""+(string)value+"\"":"\t\r\n\""+key+"\":"+"\""+(string)value+"\",");
   else return(lastline?"\t\r\n\""+key+"\":"+(string)value:"\t\r\n\""+key+"\":"+(string)value+",");
  }
//+------------------------------------------------------------------+
//| Create Withdrawing and Depositing JSON Data Object               |
//+------------------------------------------------------------------+
string CreateAccountTransactionJson(const string method,const double amount,const datetime time,const int id,const string comment)
  {
   string main="{"
               +GetLine("type",method)
               +GetLine("amount",amount)
               +GetLine("time",TimeToString(time,TIME_SECONDS|TIME_DATE))
               +GetLine("transaction_id_from_provider",(string)id)
               +GetLine("comment",comment,true)
               +"}";
   return(main);
  }
//+------------------------------------------------------------------+
//| Create Withdrawing and Depositing JSON Data Object               |
//+------------------------------------------------------------------+
string CreateOrderObjectJson(const string order_id,const string symbol,const double lotsize,
                             const double open_price,const ENUM_ORDER_TYPE order_type,const double sl_level,
                             const double tp_level,const datetime expiry,const datetime open_time,const datetime closed_time)
  {
   string dir="SELL",type="LIMIT";
   if(order_type==OP_BUY|| order_type==OP_BUYSTOP|| order_type==OP_BUYLIMIT) dir="BUY";
   if(order_type== OP_BUYLIMIT|| order_type == OP_SELLLIMIT) type="LIMIT";
   else if(order_type==OP_BUYSTOP || order_type==OP_SELLSTOP) type="STOP";

   string main="{"
               +GetLine("order_id_from_provider",order_id)
               +GetLine("account_id",AccountID)
               +"\"trade_id\":null,"
               +GetLine("trade_id_from_provider",order_id)
               +GetLine("instrument_id_from_provider",symbol)
               +GetLine("units",lotsize)
               +GetLine("currency",symbol)
               +GetLine("price",open_price)
               +GetLine("execution_price",open_price)
               +GetLine("direction",dir)//
               +GetLine("stop_loss",sl_level)
               +GetLine("take_profit",tp_level)
               +GetLine("trailing_stop",0)
               +GetLine("stop_loss_distance",0)
               +GetLine("take_profit_distance",0)
               +GetLine("trailing_stop_distance",0)
               +GetLine("order_type",type)
               +GetLine("status",order_type>OP_SELL?"PENDING":"FILLED")
               +GetLine("expire_at",expiry>0?TimeToString(expiry,TIME_SECONDS|TIME_DATE):(string)0)
               +GetLine("created_at_from_provider",open_time>0?TimeToString(open_time,TIME_SECONDS|TIME_DATE):(string)0)
               +GetLine("closed_at_from_provider",closed_time>0?TimeToString(closed_time,TIME_SECONDS|TIME_DATE):(string)0,true)
               +"}";
   return(main);
  }
//+------------------------------------------------------------------+
//| Create a trade object in JSON                                    |
//+------------------------------------------------------------------+
string CreateTradeObjectJson(const string order_id,const string symbol,const double lotsize,
                             const double open_price,const double closed_price,const double PnL,const ENUM_ORDER_TYPE order_type,const double sl_level,
                             const double tp_level,const datetime open_time,const datetime closed_time,const double commission,const double rollover,const double other_fees
                             )
  {
   double spread_cost=SymbolInfoInteger(symbol,SYMBOL_SPREAD)*Point*SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE)*lotsize;
   string dir="SELL";
   if(order_type==OP_BUY || order_type==OP_BUYSTOP || order_type==OP_BUYLIMIT) dir="BUY";

   string type="";
   if(order_type==OP_BUYLIMIT || order_type==OP_SELLLIMIT) type="LIMIT";
   else if(order_type==OP_BUYSTOP || order_type==OP_SELLSTOP) type="STOP";

   string main="{"
               +GetLine("trade_id_from_provider",order_id)
               +GetLine("account_id",AccountID)
               //+"\"trade_id\":null,"
               +GetLine("instrument_id_from_provider",symbol)
               +GetLine("direction",dir)
               +GetLine("type",order_type<=OP_SELL?"MARKET":type)
               +GetLine("units",lotsize)
               +GetLine("currency",StringSubstr(symbol,3,3))
               +GetLine("open_price",open_price)
               +GetLine("closed_price",closed_time>0?closed_price:0)
               +GetLine("profit_loss",closed_time>0?PnL:0.0)
               +GetLine("open_profit_loss",closed_time>0?0:PnL)
               +GetLine("rollover",rollover)
               +GetLine("commission",commission)
               +GetLine("other_fees",other_fees)
               +GetLine("spread_cost",spread_cost)
               +GetLine("status",closed_time>0?(order_type>OP_SELL?"CANCELLED":"CLOSED"):"OPEN")
               +GetLine("balance_at_opening",AccountBalance()-PnL)
               +GetLine("stop_loss",sl_level)
               +GetLine("take_profit",tp_level)
               +GetLine("trailing_stop",0)
               +GetLine("stop_loss_distance",0)
               +GetLine("take_profit_distance",0)
               +GetLine("trailing_stop_distance",0)
               +GetLine("created_at_from_provider",open_time>0?TimeToString(open_time,TIME_SECONDS|TIME_DATE):(string)0)
               +GetLine("closed_at_from_provider",closed_time>0?TimeToString(closed_time,TIME_SECONDS|TIME_DATE):(string)0,true)
               +"}";

   return(main);
  }
//+------------------------------------------------------------------+
//| Create currently opened order list                               |
//+------------------------------------------------------------------+
string CreateOpenedOrderListJson()
  {
   double units;
   string json="{"
               +GetLine("version",1)
               +GetLine("delete_data_not_in_list",true)
               +"\"data\":[";
   int x=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS)) continue;
      if(OrderType()<=OP_SELL) continue;

      if(x>0)json+=",";
      units=OrderLots()*MarketInfo(OrderSymbol(), MODE_LOTSIZE);
      json+=CreateOrderObjectJson((string)OrderTicket(),OrderSymbol(),units,OrderOpenPrice(),(ENUM_ORDER_TYPE)OrderType(),OrderStopLoss(),OrderTakeProfit(),OrderExpiration(),OrderOpenTime(),OrderCloseTime());
      x++;
     }

   json+="] }";

//if(x==0) return("");

   return(json);
  }
//+------------------------------------------------------------------+
//| Create currently opened and closed trade list                    |
//+------------------------------------------------------------------+
string CreateTradesListJson(const bool firstRun)
  {
   double units;
   string json="{"
               +GetLine("version",1)
               +GetLine("delete_data_not_in_list",firstRun)
               +"\"data\":[";

   datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE|TIME_DATE));
   int x=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS)) continue;
      if(OrderType()>OP_SELL) continue;

      if(x++>0)json+=",";
      units=OrderLots()*MarketInfo(OrderSymbol(), MODE_LOTSIZE);
      json+=CreateTradeObjectJson((string)OrderTicket(),OrderSymbol(),units,OrderOpenPrice(),OrderClosePrice(),OrderProfit(),(ENUM_ORDER_TYPE)OrderType(),OrderStopLoss(),OrderTakeProfit(),
                                  OrderOpenTime(),OrderCloseTime(),OrderCommission(),OrderSwap(),0);
     }

   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()=="" || OrderSymbol()==NULL) continue;
      if(!firstRun){if(OrderCloseTime()<today) continue;}
      //if(OrderType()>OP_SELL) continue;

      if(x++>0)json+=",";
      units=OrderLots()*MarketInfo(OrderSymbol(), MODE_LOTSIZE);
      json+=CreateTradeObjectJson((string)OrderTicket(),OrderSymbol(),units,OrderOpenPrice(),OrderClosePrice(),OrderProfit(),(ENUM_ORDER_TYPE)OrderType(),OrderStopLoss(),OrderTakeProfit(),
                                  OrderOpenTime(),OrderCloseTime(),OrderCommission(),OrderSwap(),0);
     }

   json+="] }";

   if(x==0) return("");

   return(json);
  }
//+------------------------------------------------------------------+
