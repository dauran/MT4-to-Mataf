//+------------------------------------------------------------------+
//|                                                      account.mqh |
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
#include <WinUser32.mqh>

//+------------------------------------------------------------------+
//| Get new token                                                    |
//+------------------------------------------------------------------+
bool GetToken()
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl = url+"/api/user/login";
   string headers = getHeaders(H_CONNECT);
   string str;
   char data[];

   parser["email"]    = email;
   parser["password"] = password;
   parser.Serialize(str);

   ArrayResize(data,StringToCharArray(str,data,0,-1,CP_UTF8)-1);
   int result=WebRequest("POST",fullUrl,headers,api_call_timeout,data,data,headers);

   if(parser.Deserialize(data))
     {
      token   = parser["data"]["token"].ToStr();
      id_user = (int)parser["data"]["id_user"].ToInt();
      if(parser["api_version"].ToDbl()>api_version)
         MessageBox("Please update your EA. Your version: "+(string)api_version+", current version: "+parser["api_version"].ToStr());
      else
         Print("Your EA is up to date");

     }
   else
     {
      Print("Failed to get Token from API");
      return(false);
     }

   return(true);
  }
//+------------------------------------------------------------------+
//| Refresh the token                                                |
//+------------------------------------------------------------------+
bool RefreshToken()
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl = url+"/api/user/refreshToken";
   string headers = getHeaders(H_POST);

   char data[];
   string str="";

   parser["id_user"] = id_user;
   parser["token"]   = token;
   parser.Serialize(str);

   ArrayResize(data,StringToCharArray(str,data,0,-1,CP_UTF8)-1);
   int result=WebRequest("POST",fullUrl,headers,api_call_timeout,data,data,headers);

   if(parser.Deserialize(data))
     {
      token=parser["data"]["token"].ToStr();
      id_user=(int)parser["data"]["id_user"].ToInt();
     }
   else
     {
      Print("Failed to Deserialize");
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void updateBalanceHistory(CJAVal &account)
  {
   int      iOrder=0, iAccountBalance=0, iFundHistory=0, iBalanceHistory=0, iBalance;
   double   balance        = 0;
   double   variation      = 0;
   double   total_deposits = 0;
   double   total_withdraw = 0;
   string   created_time   = "";
   datetime transactiontime;

   for(iOrder=0; iOrder<OrdersHistoryTotal(); iOrder++)
     {
      if(OrderSelect(iOrder,SELECT_BY_POS,MODE_HISTORY))
        {
         if(created_time=="")
            created_time=dateToGMT(OrderOpenTime());

         variation = OrderProfit()+OrderCommission()+OrderSwap();
         if(variation!=0)
           {
            balance += variation;

            //-- Transaction time is the close time for a trade and the open time for a deposit/withdraw
            transactiontime = (OrderType()==6) ? OrderOpenTime() : OrderCloseTime();

            //--- Get all the deal properties
            balanceHistory[iBalanceHistory]["time"]                         = dateToGMT((datetime)transactiontime);
            balanceHistory[iBalanceHistory]["balance"]                      = balance;
            balanceHistory[iBalanceHistory]["variation"]                    = variation;
            balanceHistory[iBalanceHistory]["transaction_id_from_provider"] = OrderTicket();
            balanceHistory[iBalanceHistory]["comment"]                      = OrderSymbol() +" "+ OrderComment() + ", open:"+dateToGMT((datetime)OrderOpenTime())+", close:"+dateToGMT((datetime)OrderCloseTime());
            iBalanceHistory++;
            //account["data"]["balance_history"][iAccountBalance++] = balanceHistory[iBalanceHistory++];
            if(OrderType()==6) //might be "Deposit" or "Withdraw" but also "Interest rates" and probably other operation types. Unfortunately I didn't find a way to filter those orders :(
              {
               if(OrderProfit()>0)
                 {
                  total_deposits                          += OrderProfit();
                  account["data"]["funds"]["history"][iFundHistory++] = CreateAccountTransactionJson("FUNDING",OrderProfit(),OrderCloseTime(),OrderTicket(),OrderComment());
                 }
               else
                 {
                  total_withdraw                          += MathAbs(OrderProfit());
                  account["data"]["funds"]["history"][iFundHistory++] = CreateAccountTransactionJson("WITHDRAW",OrderProfit(),OrderCloseTime(),OrderTicket(),OrderComment());
                 }
              }
           }
        }
     }

   SortBalanceHistory(); //-- Because it may not be in the right order

   for(iBalance=0; iBalance<balanceHistory.Size(); iBalance++)
      account["data"]["balance_history"][iBalance] = balanceHistory[iBalance];

   account["data"]["created_at_from_provider"] = created_time;
   account["data"]["profit_loss"]              = AccountBalance()-(total_deposits-total_withdraw);
   account["data"]["funds"]["deposit"]         = total_deposits;
   account["data"]["funds"]["withdraw"]        = -1*total_withdraw;

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SortBalanceHistory()
  {
   CJAVal tmp(NULL,jtUNDEF);
   double balance=0;

   for(int iBalance1=0; iBalance1<(balanceHistory.Size()-1); iBalance1++)
     {
      for(int iBalance2=iBalance1+1; iBalance2<balanceHistory.Size(); iBalance2++)
        {
         if(balanceHistory[iBalance1]["time"].ToStr() > balanceHistory[iBalance2]["time"].ToStr())
           {
            tmp                       = balanceHistory[iBalance1];
            balanceHistory[iBalance1] = balanceHistory[iBalance2];
            balanceHistory[iBalance2] = tmp;
           }
        }
     }

//-- update the balance
   for(int iBalance1=0; iBalance1<balanceHistory.Size(); iBalance1++)
     {
      balance = balance + balanceHistory[iBalance1]["variation"].ToDbl();
      balanceHistory[iBalance1]["balance"] = balance;
     }

  }
//+------------------------------------------------------------------+
//| Create new account/update existing                               |
//+------------------------------------------------------------------+
bool CreateAccount(const bool firstRun=true)
  {
   CJAVal parser(NULL,jtUNDEF);
   string fullUrl=url+"/api/trading/accounts";
   string headers= getHeaders(H_POST);

   char data[];
   string str="";
   int hwindow=GetAncestor(WindowHandle(Symbol(),Period()),2);
   if(hwindow!=0)
     {
      SetForegroundWindow(hwindow); //active the terminal (the terminal must be the active window)
      Sleep(100);
      SendMessageA(hwindow,WM_COMMAND,33058,0);
      Sleep(100);
     }

   parser["version"]                          = api_version;
   parser["date"]                             = dateToGMT(TimeCurrent());

   parser["data"]["account_id_from_provider"] = (string)AccountNumber();
   parser["data"]["provider_name"]            = AccountCompany();
   parser["data"]["source_name"]              = SOURCE;
   parser["data"]["user_id_from_provider"]    = (string)AccountNumber();
   parser["data"]["account_alias"]            = AccountAlias;
   parser["data"]["account_name"]             = AccountName();
   parser["data"]["currency"]                 = AccountCurrency();
   parser["data"]["is_live"]                  = !IsDemo();
   parser["data"]["is_active"]                = true;
   parser["data"]["balance"]                  = (float)AccountBalance();
   parser["data"]["balance_history"][0]       = 0; //calulated in updateBalanceHistory
   parser["data"]["profit_loss"]              = 0; //calulated in updateBalanceHistory
   parser["data"]["open_profit_loss"]         = AccountProfit();
   parser["data"]["funds"]["deposit"]         = 0; //calulated in updateBalanceHistory
   parser["data"]["funds"]["withdraw"]        = 0; //calulated in updateBalanceHistory
   parser["data"]["funds"]["history"][0]      = 0; //calulated in updateBalanceHistory
   parser["data"]["created_at_from_provider"] = 0; //calulated in updateBalanceHistory

   updateBalanceHistory(parser);

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
            PrintFormat("Connected to Mataf, Account ID: %d",AccountID);
        }
     }
   else
     {
      Print("Failed to Deserialize");
      return(false);
     }

   return(true);
  }
//+------------------------------------------------------------------+
//| Create Withdrawing and Depositing JSON Data Object               |
//+------------------------------------------------------------------+
CJAVal CreateAccountTransactionJson(const string method,const double amount,const datetime time,const int id,const string comment)
  {
   CJAVal parser(NULL,jtUNDEF);
   parser["type"]=method;
   parser["amount"]=amount;
   parser["time"]=dateToGMT(time);
   parser["transaction_id_from_provider"]=(string)id;
   parser["comment"]=comment;

   return(parser);
  }
//+------------------------------------------------------------------+
