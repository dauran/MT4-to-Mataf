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
#define   VERSION   "1.07"
#define   SOURCE    "MT4"

#property copyright "Mataf.net"
#property link      "https://www.mataf.net"
#property version   VERSION
#property strict
#include "include/account.mqh"
#include "include/JAson.mqh"
#include "include/pending-order.mqh"
#include "include/trades.mqh"

#import "user32.dll"
int GetAncestor(int hWnd,int gaFlags);
int SetForegroundWindow(int hWnd);
int SendMessageA(int hWnd,int Msg,int wParam,int lParam);
#import

enum ENUM_HEADER_TYPE
  {
   H_CONNECT         = 0,
   H_GET             = 1,
   H_POST            = 2,
   H_PUT             = 3
  };

//--- input parameters
input string      email            = "";                      // Email
input string      password         = "";                      // Password
input string      AccountAlias     = "Account MT4";           // Alias
input string      url              = "https://www.mataf.io";  // URL
input int         updateFrequency  = 900;                     // Update Interval(in seconds)
input int         api_call_timeout = 60000;                   // Time out

string token             = "";
int    id_user;
double api_version       = (double)VERSION;
int    AccountID;
bool   previous_finished = true;
bool   connected         = false;
CJAVal balanceHistory(NULL,jtUNDEF);
//+------------------------------------------------------------------+
//| File Type                                                        |
//+------------------------------------------------------------------+
enum ENUM_FILE_TYPE
  {
   TOKEN,
   USER_ID,
   ACCOUNT_ID
  };
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
   previous_finished=false;
   Comment("Connect to Mataf...");
   GetToken();

   if(!CreateAccount())
     {
      //---trying again with a fresh token
      Comment("Connection to Mataf failed... Try again...");
      GetToken();
      if(!CreateAccount())
        {
         Comment("Connection to Mataf Failed!");
         return(INIT_FAILED);
        }
     }

   Comment("Connected to Mataf, Send trades data...");
   UpdateTradesList(true);
   Comment("Connected to Mataf, Send trades data, Send orders data...");
   UpdatePendingOrderList();
   connected=true;
   previous_finished=true;

   Comment("Data sent to Mataf...");
   Sleep(500);
   Comment("");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Send request at given frequency                                  |
//+------------------------------------------------------------------+
int OnTickSimulated()
  {
   previous_finished=false;
   Comment("Connect to Mataf...");
   if(!CreateAccount())
     {
      //---trying again with a fresh token
      Comment("Connection to Mataf failed... Try again...");
      GetToken();
      if(!CreateAccount())
        {
         Comment("Connection to Mataf Failed!");
         return(INIT_FAILED);
        }
     }

   Comment("Connected to Mataf, Send orders data...");
   if(!UpdatePendingOrderList())
     {
      Sleep(10);
      UpdatePendingOrderList();
     }
   Comment("Connected to Mataf, Send orders data, Send trades data...");
   if(!UpdateTradesList())
     {
      Sleep(10);
      UpdateTradesList();
     }
   previous_finished=true;
   Comment("Connected to Mataf, Send orders data, Send trades data... SENT");
   return(INIT_SUCCEEDED);

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string getHeaders(ENUM_HEADER_TYPE type)
  {
   string headers;

   switch(type)
     {
      case H_CONNECT:
         headers = StringFormat("Content-Type: application/json\r\n X-Mataf-api-version: %2.f\r\n X-Mataf-source: %s",api_version,SOURCE);
         break;
      case H_PUT:
         headers = StringFormat("Content-Type: application/json\r\n X-Mataf-api-version: %2.f\r\n X-Mataf-source: %s\r\n X-Mataf-token: %s\r\n X-Mataf-id: %d\r\n X-HTTP-Method-Override: PUT",api_version,SOURCE,token,id_user);
         break;
      case H_POST:
      case H_GET:
      default:
         headers = StringFormat("Content-Type: application/json\r\n X-Mataf-api-version: %2.f\r\n X-Mataf-source: %s\r\n X-Mataf-token: %s\r\n X-Mataf-id: %d",api_version,SOURCE,token,id_user);
         break;
     }
   return (headers);

  }

//+------------------------------------------------------------------+
//| Get the current time stamp                                       |
//+------------------------------------------------------------------+
datetime GetLastActiveTimeStamp()
  {
   return(0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double balanceSearch(string date)
  {
   int i=0;

   for(i=0; i<balanceHistory.Size()-1; i++)
      if(balanceHistory[i]["time"].ToStr()>=date)
         break;

   return balanceHistory[i]["balance"].ToDbl();
  }
//+------------------------------------------------------------------+
//| Convert the date to GMT                                          |
//+------------------------------------------------------------------+
string dateToGMT(datetime dateToConvert)
  {
   float GMTOffset = (float)(TimeGMT() - TimeCurrent());
   return dateToConvert>0? displayDate((datetime)(dateToConvert + GMTOffset)):(string)0;
  }

//+------------------------------------------------------------------+
//| Display a date with the correct format                           |
//+------------------------------------------------------------------+
string displayDate(datetime dateToDisplay)
  {
   string date = dateToDisplay>0 ? TimeToString(dateToDisplay,TIME_SECONDS|TIME_DATE) : (string)0;
   StringReplace(date,".","-");
   return date;
  }
//+------------------------------------------------------------------+