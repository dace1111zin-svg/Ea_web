#property copyright "Copyright 2026, Daj Account Soon...!"
#property link      "https://www.mql5.com"
#property version   "5.07"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade trade;
CPositionInfo positionInfo;

enum ENUM_LOT_MODE {
    MODE_FIBO,              // Fibonacci Progression
    MODE_HYBRID_FIBO,       // Hybrid Fibonacci-Martingale
    MODE_HYBRID_TRANSITION  // Hybrid Transition (Adding Multiplier)
}; 
enum ENUM_TP_MODE {
    MODE_FIXED_PIPS,        // Fixed Take Profit Pips
    MODE_TRAILING,          // Trailing Basket Take Profit
    MODE_ADAPTIVE_ATR       // Adaptive ATR Take Profit
};
enum ENUM_SESSION_MODE {
    SESSION_24H,            // 24 Hours Trading (24/7)
    SESSION_CUSTOM          // Custom Session Hours (Cambodia Time)
};

// ==================================================================
// ?? ??????????????????????????????? (LICENSE PROTECTION SYSTEM)
// ==================================================================
int Allowed_Accounts[] = { 263278853, 263426504, 413789211 ,413789211,415868928 }; 
datetime Allowed_ExpiryDate = D'2026.12.31 23:59'; 
const int HybridStartStepLayer = 7;     

input group "=== LOT SIZE   ===";
input double BaseLotSize                  = 0.01;
input double LotMultiplier                = 1.3;     
input int    MultiplierCapLayer           = 8;    
input ENUM_LOT_MODE LotCalculatedMode     = MODE_FIBO; 

input group "=== MULTIPLIER   ===";
input bool   UseDynamicLotByEquity        = true;
input double HardMaxLotSize               = 0.10;       
input double AutoLotEquityBase            = 500.0; 

input group "=== STOCHASTIC FILTER ===";
input bool   EnableStochFilter            = true;   
input int    StochKPeriod                 = 14;     
input int    StochDPeriod                 = 3;      
input int    StochSlowing                 = 3;    
input double StochOverbought              = 80.0;  
input double StochOversold                = 20.0;  
input bool   StochFirstEntryOnly          = true;

input group "=== BOLLINGER BANDS ===";
input int    BBPeriod                     = 20;
input double BBDeviation                  = 2.0; 
input int    BBwidthLookback              = 50;
input double BBWidthMasterMultiplier      = 1.5;

input group "=== ADAPTIVE PIP STEP ===";
input int    ATRPeriod                    = 14; 
input double ATRSimpleMultiplier          = 2.0;
input int    ATRPercentileLookback        = 50; 
input int    RangeFastBars                = 10;        
input int    RangeSlowBars                = 50;      
input double PriceRangeMasterMultiplier   = 2.25;    
input double MinAdaptiveStepPips          = 20.0;     
input double MaxAdaptiveStepPips          = 150.0;    
input double StepSmoothingAlpha           = 0.3;    
input double StepMaxIncreasePctPerUpdate  = 30.0;    
input double StepMaxDecreasePctPerUpdate  = 20.0;
input double SpreadMinStepMultiplier      = 3.0;     
       
input group "=== LAYER BASED MAX STEP CAP ===";
input bool   UseLayerBasedMaxStepCap      = true;    
input int    LayerCapBlockSize            = 5;        
input double LayerCapBlockPips            = 200.0;  
input double LayerCapHardMaxPips          = 300.0;   

input group "=== ZONE RESTRICTION ===";
input bool   EnableZoneRestriction        = true;  
     
input group "=== EQUITY PROTECTION ===";
input bool   EnableEquityProtection       = true;    
input double StopLossDrawdownPercent      = 15.0; 

input group "=== TRADING DIRECTION ===";
input bool   EnableBuy                    = true;   
input ulong  BuyMagicNumber               = 1111; 
input bool   EnableSell                   = true;              
input ulong  SellMagicNumber              = 2222;

input group "=== SAFETY FILTERS ===";
input bool   EnableSpreadFilter           = true;    
input double MaxSpreadPips                = 30.0;          
input bool   CheckMarginBeforeTrade       = true;     
input double MinFreeMarginPercentRequired = 60.0;     
input bool   PauseOnExtremeVolatility     = true;    
input double PauseIfATRMulAboveNormal     = 3.5;     
input int    ATRNormalLookbackBars        = 200;    

input group "=== BASKET TAKE PROFIT ===";
input bool   EnableBasketTakeProfit       = true;   
input ENUM_TP_MODE BasketTakeProfitMode   = MODE_FIXED_PIPS; 
input double BasketTP_FixedPips           = 20.0;   
input int    BasketTP_ATRSmoothPeriod     = 14;   
input double BasketTP_ATRMultiplierK      = 0.1;
input double TrailingPipsPercentage       = 20.0;

input group "=== SMART GRID REDUCTION ===";
input bool   EnableGridReduction          = true;    
input int    MinLayersForReduction        = 4;        
input double ReductionProfitPips          = 2.0;     

input group "=== NEWS FILTER ===";
input bool   EnableNewsFilter             = true;    
input int    StopBeforeNewsMinutes        = 30;      
input int    StopAfterNewsMinutes         = 30;      

input group "=== SESSION FILTER ===";
input ENUM_SESSION_MODE SessionTradingMode    = SESSION_24H; // ???????????? (SESSION_24H ? SESSION_CUSTOM)
input string            AsiaSessionLocal      = "05:00-03:00";  // ??????????? (??????? SESSION_CUSTOM) 

int atrHandle   = INVALID_HANDLE;
int bbHandle    = INVALID_HANDLE;
int stochHandle = INVALID_HANDLE;

double HybridVolatilityThreshold = 1.1; 
double FinalAdaptiveStepPips     = 20.0;  

double MaxBuyBasketProfitPips  = 0.0;
double MaxSellBasketProfitPips = 0.0;

// Global control flags
bool   g_EAPaused = false;
bool   g_DBCollapsed = false;

// Global news watchdog variables
datetime g_nextNewsTime = 0;
string   g_newsEvent = "NONE";
string   g_newsCountdown = "00:00:00";
string   g_newsStatus = "SAFE";

bool   CheckSafetyFilters();
void   CalculateMarketVolatility();
void   CalculateAdaptiveStep();
void   CheckEntryConditions();
void   CheckBasketPositions();
void   ApplyGridReduction(ulong magic);
double CalculateLotSize(ulong magic, int currentLayers);
int    GetOpenLayersCount(ulong magic);
double GetLastOrderPrice(ulong magic);
double GetLastOrderLot(ulong magic);
bool   IsNewCandle(); 
bool   IsInsideSession();
void   CloseAllPositions();
void   CloseBasketByMagic(ulong magic);
bool   GetPositionPriceRange(ulong magic, double &minPrice, double &maxPrice);
int    GetFibonacci(int n);
bool   AccountIsCent();
void   FetchNewsFromWeb();
bool   IsNewsTime();
double GetMonthlyProfitLocal();

// UI Dashboard Helper Functions
void   CreatePanel(string name, int x, int y, int cx, int cy, color bg);
void   CreateLabel(string name, string text, int x, int y, int fontSize, color c, bool bold=false);
void   CreateLine(string name, int x, int y, int cx, color c);
void   CreateButton(string name, string text, int x, int y, int cx, int cy, color bg, color tc);
void   ClearDashboard();
void   DrawDashboard();

// ??????????????????????????? Object ???? Dashboard (????????????????????????????)
#define DB_PREFIX "SB_"

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    if(TimeCurrent() >= Allowed_ExpiryDate)
    {
        Alert("? LICENSE ERROR: This EA has expired! Please contact the developer.");
        ExpertRemove();
        return(INIT_FAILED);
    }

    int currentAccountNumber = (int)AccountInfoInteger(ACCOUNT_LOGIN);
    bool isAccountValid = false;
    int totalAllowedAccounts = ArraySize(Allowed_Accounts);
    
    for(int i = 0; i < totalAllowedAccounts; i++)
    {
        if(currentAccountNumber == Allowed_Accounts[i])
        {
            isAccountValid = true;
            break;
        }
    }
    
    if(!isAccountValid)
    {
        Alert(StringFormat("? LICENSE ERROR: Account %d is NOT authorized to use this EA!", currentAccountNumber));
        ExpertRemove();
        return(INIT_FAILED);
    }

    atrHandle = iATR(_Symbol, _Period, ATRPeriod); 
    if(atrHandle == INVALID_HANDLE) { Print("Error: iATR Failed!"); return(INIT_FAILED); }
    
    bbHandle = iBands(_Symbol, _Period, BBPeriod, 0, BBDeviation, PRICE_CLOSE);
    if(bbHandle == INVALID_HANDLE) { Print("Error: iBands Failed!"); return(INIT_FAILED); }

    stochHandle = iStochastic(_Symbol, _Period, StochKPeriod, StochDPeriod, StochSlowing, MODE_SMA, STO_LOWHIGH);
    if(stochHandle == INVALID_HANDLE) { Print("Error: iStochastic Failed!"); return(INIT_FAILED); }

    // Reset ?????????????????? Trailing Tracker
    MaxBuyBasketProfitPips = 0.0;
    MaxSellBasketProfitPips = 0.0;
    g_EAPaused = false;
    g_DBCollapsed = false;

    // Fetch initial news
    if(EnableNewsFilter) FetchNewsFromWeb();

    ClearDashboard();

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(atrHandle   != INVALID_HANDLE) IndicatorRelease(atrHandle);
    if(bbHandle    != INVALID_HANDLE) IndicatorRelease(bbHandle);
    if(stochHandle != INVALID_HANDLE) IndicatorRelease(stochHandle);
    
    ClearDashboard();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!CheckSafetyFilters()) return; 
    CalculateMarketVolatility();
    CalculateAdaptiveStep();
    
    if(EnableBasketTakeProfit) CheckBasketPositions();
    
    bool newsPause = IsNewsTime();
    
    if(!g_EAPaused && !newsPause)
    {
        if(IsNewCandle())
        {
            CheckEntryConditions();
        }
        ApplyGridReduction(BuyMagicNumber);
        ApplyGridReduction(SellMagicNumber);
    }

    DrawDashboard();
}

//+------------------------------------------------------------------+
//| Safety filters check                                             |
//+------------------------------------------------------------------+
bool CheckSafetyFilters()
{
    if(EnableSpreadFilter)
    {
        int currentSpreadPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
        double currentSpreadPips = (double)currentSpreadPoints / 10.0;
        if(currentSpreadPips > MaxSpreadPips) return false; 
    }
    if(EnableEquityProtection)
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
        if(balance > 0)
        {
            double currentDrawdownPercent = ((balance - equity) / balance) * 100.0;
            if(currentDrawdownPercent >= StopLossDrawdownPercent) { CloseAllPositions(); return false; }
        }
    }
    if(CheckMarginBeforeTrade)
    {
        double margin     = AccountInfoDouble(ACCOUNT_
<truncated 48847 bytes>

NOTE: The output was truncated because it was too long. Use a more targeted query or a smaller range to get the information you need.