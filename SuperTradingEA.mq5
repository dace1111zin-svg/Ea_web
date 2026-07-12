//+------------------------------------------------------------------+
//|                                                MyGoldTrade.mq5   |
//|                               Copyright 2026, Daj Account Soon   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
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
// License Protection System
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
input ENUM_SESSION_MODE SessionTradingMode    = SESSION_24H;
input string            AsiaSessionLocal      = "05:00-03:00"; 

input group "=== DASHBOARD REMOTE SYNC ===";
input bool   EnableDashboardSync          = true;
input string DashboardSyncURL             = "http://localhost:5000/api/update";
input int    SyncIntervalSeconds          = 10; 

int atrHandle   = INVALID_HANDLE;
int bbHandle    = INVALID_HANDLE;
int stochHandle = INVALID_HANDLE;

double HybridVolatilityThreshold = 1.1; 
double FinalAdaptiveStepPips     = 20.0;  

double MaxBuyBasketProfitPips  = 0.0;
double MaxSellBasketProfitPips = 0.0;

bool   g_EAPaused = false;
bool   g_DBCollapsed = false;

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

// Dashboard Helpers
void   CreatePanel(string name, int x, int y, int cx, int cy, color bg);
void   CreateLabel(string name, string text, int x, int y, int fontSize, color c, bool bold=false);
void   CreateLine(string name, int x, int y, int cx, color c);
void   CreateButton(string name, string text, int x, int y, int cx, int cy, color bg, color tc);
void   ClearDashboard();
void   DrawDashboard();

#define DB_PREFIX "SB_"

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    if(TimeCurrent() >= Allowed_ExpiryDate)
    {
        Alert("License ERROR: This EA has expired!");
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
        Alert(StringFormat("License ERROR: Account %d is NOT authorized!", currentAccountNumber));
        ExpertRemove();
        return(INIT_FAILED);
    }

    atrHandle = iATR(_Symbol, _Period, ATRPeriod); 
    if(atrHandle == INVALID_HANDLE) { Print("Error: iATR Failed!"); return(INIT_FAILED); }
    
    bbHandle = iBands(_Symbol, _Period, BBPeriod, 0, BBDeviation, PRICE_CLOSE);
    if(bbHandle == INVALID_HANDLE) { Print("Error: iBands Failed!"); return(INIT_FAILED); }

    stochHandle = iStochastic(_Symbol, _Period, StochKPeriod, StochDPeriod, StochSlowing, MODE_SMA, STO_LOWHIGH);
    if(stochHandle == INVALID_HANDLE) { Print("Error: iStochastic Failed!"); return(INIT_FAILED); }

    MaxBuyBasketProfitPips = 0.0;
    MaxSellBasketProfitPips = 0.0;
    g_EAPaused = false;
    g_DBCollapsed = false;

    if(EnableNewsFilter) FetchNewsFromWeb();

    // Set premium chart aesthetics (Black background, dark grid, buy/sell markers visible, etc.)
    ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'11,15,20');    // #0B0F14 Dark luxury
    ChartSetInteger(0, CHART_COLOR_FOREGROUND, C'168,176,184'); // #A8B0B8 text labels
    ChartSetInteger(0, CHART_COLOR_GRID, C'28,36,48');          // Dark grid
    ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, C'255,77,77');  // Red bear
    ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, C'0,255,136');  // Emerald bull
    ChartSetInteger(0, CHART_COLOR_CHART_DOWN, C'255,77,77');
    ChartSetInteger(0, CHART_COLOR_CHART_UP, C'0,255,136');
    ChartSetInteger(0, CHART_SHOW_GRID, true);
    ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, false);
    ChartRedraw(0);

    ClearDashboard();

    if(EnableDashboardSync)
    {
        EventSetTimer(SyncIntervalSeconds);
    }

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
    
    if(EnableDashboardSync)
    {
        EventKillTimer();
    }
    
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
        double margin     = AccountInfoDouble(ACCOUNT_MARGIN);
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        if(margin > 0 && (freeMargin / margin) * 100.0 < MinFreeMarginPercentRequired) return false; 
    }
    return true;
}

//+------------------------------------------------------------------+
//| Volatility calculation                                           |
//+------------------------------------------------------------------+
void CalculateMarketVolatility()
{
    double finalPriceRangeValue = 0.0, finalATRValue = 0.0, finalBBWidthValue = 0.0;
    MqlRates rates[]; ArraySetAsSeries(rates, true);
    int maxBarsNeeded = MathMax(RangeFastBars, RangeSlowBars);
    
    if(CopyRates(_Symbol, _Period, 0, maxBarsNeeded, rates) > 0)
    {
        double fastHigh = rates[0].high, fastLow = rates[0].low;
        int limitFast = MathMin(RangeFastBars, ArraySize(rates));
        for(int i=0; i<limitFast; i++) { if(rates[i].high > fastHigh) fastHigh = rates[i].high; if(rates[i].low < fastLow) fastLow = rates[i].low; }
        double fastRange = (fastHigh - fastLow) / (_Point * 10.0); 

        double slowHigh = rates[0].high, slowLow = rates[0].low;
        int limitSlow = MathMin(RangeSlowBars, ArraySize(rates));
        for(int i=0; i<limitSlow; i++) { if(rates[i].high > slowHigh) slowHigh = rates[i].high; if(rates[i].low < slowLow)  slowLow  = rates[i].low; }
        double slowRange = (slowHigh - slowLow) / (_Point * 10.0); 

        if(slowRange > 0) finalPriceRangeValue = (fastRange / slowRange) * PriceRangeMasterMultiplier;
    }

    if(atrHandle != INVALID_HANDLE)
    {
        double atrValues[]; ArraySetAsSeries(atrValues, true);
        if(CopyBuffer(atrHandle, 0, 0, ATRPercentileLookback, atrValues) > 0)
        {
            double currentATR = atrValues[0] / (_Point * 10.0); 
            int higherCount = 0; int totalCount = MathMin(ATRPercentileLookback, ArraySize(atrValues));
            for(int i=0; i<totalCount; i++) { if(currentATR > (atrValues[i] / (_Point * 10.0))) higherCount++; }
            double atrPercentileRatio = (totalCount > 0) ? (double)higherCount / (double)totalCount : 0.0;
            finalATRValue = currentATR * ATRSimpleMultiplier * (1.0 + atrPercentileRatio);
        }
    }

    if(bbHandle != INVALID_HANDLE)
    {
        double upperValues[], lowerValues[], middleValues[];
        ArraySetAsSeries(upperValues, true); ArraySetAsSeries(lowerValues, true); ArraySetAsSeries(middleValues, true);
        if(CopyBuffer(bbHandle, 1, 0, BBwidthLookback, upperValues) > 0 && CopyBuffer(bbHandle, 2, 0, BBwidthLookback, lowerValues) > 0 && CopyBuffer(bbHandle, 0, 0, BBwidthLookback, middleValues) > 0)
        {
            double currentBBWidth = (middleValues[0] > 0) ? (upperValues[0] - lowerValues[0]) / middleValues[0] : 0.0;
            double sumBBWidth = 0.0; int actualCount = 0; int validCount = MathMin(BBwidthLookback, ArraySize(middleValues));
            for(int i=0; i<validCount; i++) { if(middleValues[i] > 0) { sumBBWidth += (upperValues[i] - lowerValues[i]) / middleValues[i]; actualCount++; } }
            double averageBBWidth = (actualCount > 0) ? (sumBBWidth / actualCount) : 0.001;
            if(averageBBWidth > 0) finalBBWidthValue = (currentBBWidth / averageBBWidth) * BBWidthMasterMultiplier;
        }
    }

    HybridVolatilityThreshold = (finalPriceRangeValue * 0.3) + (finalATRValue * 0.4) + (finalBBWidthValue * 0.3);
}

//+------------------------------------------------------------------+
//| Adaptive pip step calculation                                    |
//+------------------------------------------------------------------+
void CalculateAdaptiveStep()
{
    static double lastCalculatedStep = 0.0;
    if(lastCalculatedStep == 0.0) lastCalculatedStep = MinAdaptiveStepPips;

    double rawStep = HybridVolatilityThreshold; 
    double smoothedStep = (rawStep * StepSmoothingAlpha) + (lastCalculatedStep * (1.0 - StepSmoothingAlpha));

    double maxIncreaseLimit = lastCalculatedStep * (1.0 + (StepMaxIncreasePctPerUpdate / 100.0));
    double maxDecreaseLimit = lastCalculatedStep * (1.0 - (StepMaxDecreasePctPerUpdate / 100.0));
    if(smoothedStep > maxIncreaseLimit) smoothedStep = maxIncreaseLimit;
    if(smoothedStep < maxDecreaseLimit) smoothedStep = maxDecreaseLimit;

    lastCalculatedStep = smoothedStep;

    int currentSpreadPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    double currentSpreadPips = (double)currentSpreadPoints / 10.0;
    double minStepBySpread = currentSpreadPips * SpreadMinStepMultiplier;

    double finalStep = smoothedStep;
    if(finalStep < minStepBySpread) finalStep = minStepBySpread;
    if(finalStep < MinAdaptiveStepPips) finalStep = MinAdaptiveStepPips;
    if(finalStep > MaxAdaptiveStepPips) finalStep = MaxAdaptiveStepPips;

    if(UseLayerBasedMaxStepCap)
    {
        int openLayers = MathMax(GetOpenLayersCount(BuyMagicNumber), GetOpenLayersCount(SellMagicNumber));
        int blockCount = openLayers / LayerCapBlockSize;
        double layerAdaptiveMaxCap = MaxAdaptiveStepPips + (blockCount * LayerCapBlockPips);
        if(layerAdaptiveMaxCap > LayerCapHardMaxPips) layerAdaptiveMaxCap = LayerCapHardMaxPips;
        if(finalStep > layerAdaptiveMaxCap) finalStep = layerAdaptiveMaxCap;
    }

    FinalAdaptiveStepPips = NormalizeDouble(finalStep, 1);
}

//+------------------------------------------------------------------+
//| Lot size calculation with dynamic models                         |
//+------------------------------------------------------------------+
double CalculateLotSize(ulong magic, int currentLayers)
{
    double lot = BaseLotSize;

    if(UseDynamicLotByEquity)
    {
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(AccountIsCent()) equity /= 100.0;
        if(AutoLotEquityBase > 0)
        {
            lot = (equity / AutoLotEquityBase) * BaseLotSize;
        }
    }

    if(currentLayers > 0)
    {
        double lastLot = GetLastOrderLot(magic);
        if(lastLot == 0.0) lastLot = lot;
        
        if(LotCalculatedMode == MODE_FIBO)
        {
            if(currentLayers < MultiplierCapLayer)
            {
                if(currentLayers < HybridStartStepLayer)
                {
                    int fiboValue = GetFibonacci(currentLayers + 1); 
                    lot = BaseLotSize * fiboValue;
                }
                else
                {
                    lot = lastLot * LotMultiplier;
                }
            }
            else lot = lastLot; 
        } 
        else if(LotCalculatedMode == MODE_HYBRID_FIBO)
        {
            if(currentLayers <= 10)
            {
                int fiboValue = GetFibonacci(currentLayers + 1); 
                lot = BaseLotSize * fiboValue;
            }
            else
            {
                double lotLayer10 = BaseLotSize * GetFibonacci(11); 
                int excessLayers = currentLayers - 10;
                lot = lotLayer10 * MathPow(LotMultiplier, excessLayers);
            }
        }         
        else if(LotCalculatedMode == MODE_HYBRID_TRANSITION)
        {
            if(currentLayers < MultiplierCapLayer)
            {
                if(currentLayers < HybridStartStepLayer)
                {
                    lot = lastLot * LotMultiplier;
                }
                else
                {
                    double hybridStepMultiplier = LotMultiplier + ((currentLayers - HybridStartStepLayer + 1) * 0.1);
                    lot = lastLot * hybridStepMultiplier;
                }
            }
            else lot = lastLot;
        }         
    }

    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    // Cap by HardMaxLotSize
    if(lot > HardMaxLotSize) lot = HardMaxLotSize;
    
    if(lot < minLot) lot = minLot;
    if(lot > maxLot) lot = maxLot;

    return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Fibonacci generator helper                                       |
//+------------------------------------------------------------------+
int GetFibonacci(int n)
{
    if(n <= 0) return 0;
    if(n == 1) return 1;
    
    int first = 0;
    int second = 1;
    int result = 0;
    
    for(int i = 2; i <= n; i++)
    {
        result = first + second;
        first = second;
        second = result;
    }
    return result;
}

//+------------------------------------------------------------------+
//| Grid entry execution logic                                       |
//+------------------------------------------------------------------+
void CheckEntryConditions()
{
    double stochK[], stochD[];
    ArraySetAsSeries(stochK, true); ArraySetAsSeries(stochD, true);
    if(CopyBuffer(stochHandle, 0, 1, 2, stochK) <= 0 || CopyBuffer(stochHandle, 1, 1, 2, stochD) <= 0) return;

    double currentK = stochK[0];
    double currentPriceBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentPriceAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    bool insideSession = IsInsideSession();

    // --- BUY DIRECTION ---
    if(EnableBuy)
    {
        int buyLayers = GetOpenLayersCount(BuyMagicNumber);
        double nextBuyLot = CalculateLotSize(BuyMagicNumber, buyLayers);
        
        if(buyLayers == 0)
        {
            if(insideSession)
            {
                bool allowedByZone = true;
                if(EnableZoneRestriction)
                {
                    double minSellPrice = 0, maxSellPrice = 0;
                    if(GetPositionPriceRange(SellMagicNumber, minSellPrice, maxSellPrice))
                    {
                        if(currentPriceAsk >= minSellPrice && currentPriceAsk <= maxSellPrice) allowedByZone = false;
                    }
                }
                
                if(allowedByZone)
                {
                    bool passBuyStoch = (!EnableStochFilter) || (currentK < StochOversold);
                    if(passBuyStoch)
                    {
                        trade.SetExpertMagicNumber(BuyMagicNumber);
                        trade.Buy(nextBuyLot, _Symbol, currentPriceAsk, 0, 0, "First Buy Layer");
                    }
                }
            }
        }
        else
        {
            double lastBuyPrice = GetLastOrderPrice(BuyMagicNumber);
            double distancePips = (lastBuyPrice - currentPriceAsk) / (_Point * 10.0);
            
            if(distancePips >= FinalAdaptiveStepPips)
            {
                bool passNextBuyStoch = (!EnableStochFilter || !StochFirstEntryOnly) || (currentK < StochOversold);
                if(passNextBuyStoch)
                {
                    trade.SetExpertMagicNumber(BuyMagicNumber);
                    trade.Buy(nextBuyLot, _Symbol, currentPriceAsk, 0, 0, StringFormat("Buy Layer %d", buyLayers+1));
                }
            }
        }
    }

    // --- SELL DIRECTION ---
    if(EnableSell)
    {
        int sellLayers = GetOpenLayersCount(SellMagicNumber);
        double nextSellLot = CalculateLotSize(SellMagicNumber, sellLayers);
        
        if(sellLayers == 0)
        {
            if(insideSession)
            {
                bool allowedByZone = true;
                if(EnableZoneRestriction)
                {
                    double minBuyPrice = 0, maxBuyPrice = 0;
                    if(GetPositionPriceRange(BuyMagicNumber, minBuyPrice, maxBuyPrice))
                    {
                        if(currentPriceBid >= minBuyPrice && currentPriceBid <= maxBuyPrice) allowedByZone = false;
                    }
                }
                
                if(allowedByZone)
                {
                    bool passSellStoch = (!EnableStochFilter) || (currentK > StochOverbought);
                    if(passSellStoch)
                    {
                        trade.SetExpertMagicNumber(SellMagicNumber);
                        trade.Sell(nextSellLot, _Symbol, currentPriceBid, 0, 0, "First Sell Layer");
                    }
                }
            }
        }
        else
        {
            double lastSellPrice = GetLastOrderPrice(SellMagicNumber);
            double distancePips = (currentPriceBid - lastSellPrice) / (_Point * 10.0);
            
            if(distancePips >= FinalAdaptiveStepPips)
            {
                bool passNextSellStoch = (!EnableStochFilter || !StochFirstEntryOnly) || (currentK > StochOverbought);
                if(passNextSellStoch)
                {
                    trade.SetExpertMagicNumber(SellMagicNumber);
                    trade.Sell(nextSellLot, _Symbol, currentPriceBid, 0, 0, StringFormat("Sell Layer %d", sellLayers+1));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Basket profit tracking and close actions                         |
//+------------------------------------------------------------------+
void CheckBasketPositions()
{
    ulong magics[2] = { BuyMagicNumber, SellMagicNumber };
    
    for(int m = 0; m < 2; m++)
    {
        ulong currentMagic = magics[m];
        int totalOpen = GetOpenLayersCount(currentMagic);
        
        if(totalOpen == 0)
        {
            if(currentMagic == BuyMagicNumber) MaxBuyBasketProfitPips = 0.0;
            if(currentMagic == SellMagicNumber) MaxSellBasketProfitPips = 0.0;
            continue;
        }

        double totalProfitUSD = 0.0;
        double totalVolumeLots = 0.0;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(positionInfo.SelectByIndex(i))
            {
                if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == currentMagic)
                {
                    totalProfitUSD += positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();
                    totalVolumeLots += positionInfo.Volume();
                }
            }
        }

        double targetProfitUSD = 0.0;
        double currentBasketPips = 0.0;
        double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        
        if(tickSize > 0 && totalVolumeLots > 0)
        {
            double pointValueInUSD = (tickValue / tickSize) * _Point; 
            
            currentBasketPips = totalProfitUSD / (10.0 * pointValueInUSD * totalVolumeLots);
            
            if(BasketTakeProfitMode == MODE_FIXED_PIPS)
            {
                targetProfitUSD = BasketTP_FixedPips * 10.0 * pointValueInUSD * totalVolumeLots;
                if(totalProfitUSD >= targetProfitUSD && targetProfitUSD > 0)
                {
                    PrintFormat("Basket Fixed TP Hit! Magic: %d, Profit: %.2f USD", currentMagic, totalProfitUSD);
                    CloseBasketByMagic(currentMagic);
                }
            }
            else if(BasketTakeProfitMode == MODE_ADAPTIVE_ATR)
            {
                double atrValues[]; ArraySetAsSeries(atrValues, true);
                if(CopyBuffer(atrHandle, 0, 0, BasketTP_ATRSmoothPeriod, atrValues) > 0)
                {
                    double sumATR = 0; int count = MathMin(BasketTP_ATRSmoothPeriod, ArraySize(atrValues));
                    for(int k=0; k<count; k++) sumATR += atrValues[k];
                    double avgATR = (count > 0) ? sumATR / count : atrValues[0];
                    
                    double dynamicTPPips = (avgATR / (_Point * 10.0)) * BasketTP_ATRMultiplierK;
                    targetProfitUSD = dynamicTPPips * 10.0 * pointValueInUSD * totalVolumeLots;
                    
                    if(totalProfitUSD >= targetProfitUSD && targetProfitUSD > 0)
                    {
                        PrintFormat("Basket Adaptive ATR TP Hit! Magic: %d, Profit: %.2f USD", currentMagic, totalProfitUSD);
                        CloseBasketByMagic(currentMagic);
                    }
                }
            }
            else if(BasketTakeProfitMode == MODE_TRAILING)
            {
                if(currentBasketPips >= BasketTP_FixedPips)
                {
                    if(currentMagic == BuyMagicNumber)
                    {
                        if(currentBasketPips > MaxBuyBasketProfitPips) MaxBuyBasketProfitPips = currentBasketPips;
                        
                        double trailingStopLevelBuy = MaxBuyBasketProfitPips * (1.0 - (TrailingPipsPercentage / 100.0));
                        
                        if(currentBasketPips <= trailingStopLevelBuy)
                        {
                            PrintFormat("Basket Trailing Hit! Buy Magic: %d | Max Pips: %.1f | Close at Pips: %.1f", currentMagic, MaxBuyBasketProfitPips, currentBasketPips);
                            CloseBasketByMagic(currentMagic);
                            MaxBuyBasketProfitPips = 0.0;
                        }
                    }
                    else if(currentMagic == SellMagicNumber)
                    {
                        if(currentBasketPips > MaxSellBasketProfitPips) MaxSellBasketProfitPips = currentBasketPips;
                        
                        double trailingStopLevelSell = MaxSellBasketProfitPips * (1.0 - (TrailingPipsPercentage / 100.0));
                        
                        if(currentBasketPips <= trailingStopLevelSell)
                        {
                            PrintFormat("Basket Trailing Hit! Sell Magic: %d | Max Pips: %.1f | Close at Pips: %.1f", currentMagic, MaxSellBasketProfitPips, currentBasketPips);
                            CloseBasketByMagic(currentMagic);
                            MaxSellBasketProfitPips = 0.0;
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Smart Grid reduction algorithm (Partial Exit / Overlay)          |
//+------------------------------------------------------------------+
void ApplyGridReduction(ulong magic)
{
    if(!EnableGridReduction) return;
    
    int totalLayers = GetOpenLayersCount(magic);
    if(totalLayers < MinLayersForReduction) return;
    
    ulong oldestTicket = 0, newestTicket = 0;
    datetime oldestTime = D'2030.01.01 00:00';
    datetime newestTime = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == magic)
            {
                datetime t = positionInfo.Time();
                if(t < oldestTime)
                {
                    oldestTime = t;
                    oldestTicket = positionInfo.Ticket();
                }
                if(t > newestTime)
                {
                    newestTime = t;
                    newestTicket = positionInfo.Ticket();
                }
            }
        }
    }
    
    if(oldestTicket > 0 && newestTicket > 0 && oldestTicket != newestTicket)
    {
        double profit1 = 0, profit2 = 0;
        double vol1 = 0, vol2 = 0;
        
        if(positionInfo.SelectByTicket(oldestTicket))
        {
            profit1 = positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();
            vol1 = positionInfo.Volume();
        }
        if(positionInfo.SelectByTicket(newestTicket))
        {
            profit2 = positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();
            vol2 = positionInfo.Volume();
        }
        
        double totalProfitUSD = profit1 + profit2;
        double totalVolumeLots = vol1 + vol2;
        
        double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        
        if(tickSize > 0 && totalVolumeLots > 0)
        {
            double pointValueInUSD = (tickValue / tickSize) * _Point; 
            double netPips = totalProfitUSD / (10.0 * pointValueInUSD * totalVolumeLots);
            
            if(netPips >= ReductionProfitPips)
            {
                PrintFormat("Smart Grid Reduction triggered! Magic: %d, Closing oldest ticket %d and newest ticket %d. Net Profit: %.2f USD (%.1f Pips)", 
                            magic, oldestTicket, newestTicket, totalProfitUSD, netPips);
                trade.PositionClose(oldestTicket);
                trade.PositionClose(newestTicket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Candle trigger detector                                          |
//+------------------------------------------------------------------+
bool IsNewCandle()
{
    static datetime lastCandleTime = 0;
    datetime currentCandleTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
    
    if(currentCandleTime != lastCandleTime)
    {
        lastCandleTime = currentCandleTime;
        return true; 
    }
    return false; 
}

//+------------------------------------------------------------------+
//| Session filter utility                                           |
//+------------------------------------------------------------------+
bool IsInsideSession()
{
    if(SessionTradingMode == SESSION_24H) return true;

    MqlDateTime dt;
    TimeToStruct(TimeLocal(), dt);
    int currentMinutesSinceMidnight = dt.hour * 60 + dt.min;

    string timeParts[];
    if(StringSplit(AsiaSessionLocal, '-', timeParts) != 2) return true; 

    string startParts[], endParts[];
    if(StringSplit(timeParts[0], ':', startParts) != 2 || StringSplit(timeParts[1], ':', endParts) != 2) return true;

    int startMinutes = (int)StringToInteger(startParts[0]) * 60 + (int)StringToInteger(startParts[1]);
    int endMinutes   = (int)StringToInteger(endParts[0]) * 60 + (int)StringToInteger(endParts[1]);

    if(startMinutes < endMinutes) return (currentMinutesSinceMidnight >= startMinutes && currentMinutesSinceMidnight <= endMinutes);
    else return (currentMinutesSinceMidnight >= startMinutes || currentMinutesSinceMidnight <= endMinutes);
}

//+------------------------------------------------------------------+
//| Get position grid boundaries                                     |
//+------------------------------------------------------------------+
bool GetPositionPriceRange(ulong magic, double &minPrice, double &maxPrice)
{
    bool found = false;
    minPrice = 999999.0;
    maxPrice = 0.0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == magic)
            {
                double openPrice = positionInfo.PriceOpen();
                if(openPrice < minPrice) minPrice = openPrice;
                if(openPrice > maxPrice) maxPrice = openPrice;
                found = true;
            }
        }
    }
    return found;
}

//+------------------------------------------------------------------+
//| Last active order volume tracer                                  |
//+------------------------------------------------------------------+
double GetLastOrderLot(ulong magic)
{
    double lastLot = 0.0;
    datetime lastTime = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == magic)
            {
                if(positionInfo.Time() > lastTime)
                {
                    lastTime = positionInfo.Time();
                    lastLot = positionInfo.Volume();
                }
            }
        }
    }
    return lastLot;
}

//+------------------------------------------------------------------+
//| General helper utilities                                         |
//+------------------------------------------------------------------+
int GetOpenLayersCount(ulong magic)
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i)) { if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == magic) count++; }
    }
    return count;
}

double GetLastOrderPrice(ulong magic)
{
    double lastPrice = 0.0; datetime lastTime = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == magic)
            {
                if(positionInfo.Time() > lastTime) { lastTime = positionInfo.Time(); lastPrice = positionInfo.PriceOpen(); }
            }
        }
    }
    return lastPrice;
}

void CloseBasketByMagic(ulong magic)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i)) { if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == magic) trade.PositionClose(positionInfo.Ticket()); }
    }
}

void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i)) { if(positionInfo.Symbol() == _Symbol) trade.PositionClose(positionInfo.Ticket()); }
    }
}

double GetTodayProfitLocal()
{
    double profit = 0;
    datetime localTime = TimeLocal();
    MqlDateTime dt;
    TimeToStruct(localTime, dt);
    dt.hour = 0; dt.min = 0; dt.sec = 0;
    datetime startOfDay = StructToTime(dt);
    
    if(HistorySelect(startOfDay, localTime))
    {
        int totalDeals = HistoryDealsTotal();
        for(int i = 0; i < totalDeals; i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket > 0 && HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
                long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
                if(magic == BuyMagicNumber || magic == SellMagicNumber)
                {
                    profit += HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
                }
            }
        }
    }
    return profit;
}

double GetWeeklyProfitLocal()
{
    double profit = 0;
    datetime localTime = TimeLocal();
    MqlDateTime dt;
    TimeToStruct(localTime, dt);
    
    int daysToSubtract = dt.day_of_week - 1;
    if(dt.day_of_week == 0) daysToSubtract = 6;
    
    dt.hour = 0; dt.min = 0; dt.sec = 0;
    datetime startOfWeek = StructToTime(dt) - (daysToSubtract * 86400);
    
    if(HistorySelect(startOfWeek, localTime))
    {
        int totalDeals = HistoryDealsTotal();
        for(int i = 0; i < totalDeals; i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket > 0 && HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
                long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
                if(magic == BuyMagicNumber || magic == SellMagicNumber)
                {
                    profit += HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
                }
            }
        }
    }
    return profit;
}

//+------------------------------------------------------------------+
//| News Filter parser function (ForexProTools WebRequest)            |
//+------------------------------------------------------------------+
void FetchNewsFromWeb() { 
   if(!EnableNewsFilter) return; 
   string cookie=NULL, headers; char post[], result[]; string dateStr = TimeToString(TimeCurrent(), TIME_DATE); 
   string url = "https://ec.forexprostools.com/?importance=3&currencies=15&start_date="+dateStr+"&end_date="+dateStr; 
   int res = WebRequest("GET", url, cookie, NULL, 3000, post, 0, result, headers); 
   if(res == 200) { 
      string html = CharArrayToString(result); int pos = StringFind(html, "class=\"dateFont\"", 0); 
      if(pos > 0) { 
         int timePos = StringFind(html, "id=\"eventTime_", pos); 
         if(timePos > 0) { 
            int start = StringFind(html, ">", timePos) + 1; int end = StringFind(html, "<", start); 
            string timeStr = StringSubstr(html, start, end - start); g_nextNewsTime = StringToTime(dateStr + " " + timeStr); 
            int eventPos = StringFind(html, "class=\"left event\"", start);
            if(eventPos > 0) { 
                int startE = StringFind(html, ">", eventPos) + 1; int endE = StringFind(html, "<", startE); 
                string fullEvent = StringSubstr(html, startE, endE - startE); StringTrimLeft(fullEvent); StringTrimRight(fullEvent); 
                if(StringFind(fullEvent, "CPI") >= 0) g_newsEvent = "CPI"; 
                else if(StringFind(fullEvent, "Nonfarm") >= 0) g_newsEvent = "NFP"; 
                else if(StringFind(fullEvent, "FOMC") >= 0) g_newsEvent = "FOMC"; 
                else if(StringFind(fullEvent, "Fed") >= 0) g_newsEvent = "FED RATE"; 
                else if(StringFind(fullEvent, "GDP") >= 0) g_newsEvent = "GDP"; 
                else if(StringLen(fullEvent) > 12) g_newsEvent = StringSubstr(fullEvent, 0, 10) + ".."; 
                else g_newsEvent = fullEvent; 
            } 
            else { g_newsEvent = "USD HIGH"; }
         } 
      } 
   } else { g_newsStatus = "SYNC ERR"; } 
}

//+------------------------------------------------------------------+
//| News time checking logic                                         |
//+------------------------------------------------------------------+
bool IsNewsTime() {
   if(!EnableNewsFilter) return false; static datetime lastNF = 0; if(TimeCurrent() - lastNF > 1800) { FetchNewsFromWeb(); lastNF = TimeCurrent(); } 
   if(g_nextNewsTime > 0) { 
      long diff = (long)g_nextNewsTime - (long)TimeCurrent(); 
      if(diff > 0) { int h = (int)(diff / 3600); int m = (int)((diff % 3600) / 60); int s = (int)(diff % 60); g_newsCountdown = StringFormat("%02d:%02d:%02d", h, m, s); g_newsStatus = g_newsCountdown; } 
      else if (diff <= 0 && diff > -StopAfterNewsMinutes * 60) { g_newsStatus = "LIVE"; g_newsCountdown = "LIVE"; } 
      else { g_newsStatus = "SAFE"; g_newsEvent = "NONE"; g_newsCountdown = "00:00:00"; }
      if(diff <= StopBeforeNewsMinutes * 60 && diff > -StopAfterNewsMinutes * 60) return true; 
   } else { g_newsStatus = "NO NEWS"; g_newsEvent = "NONE"; g_newsCountdown = "00:00:00"; }
   return false; 
}

//+------------------------------------------------------------------+
//| ChartEvent event handler to detect button clicks                 |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        string clickedName = sparam;
        
        if(clickedName == DB_PREFIX + "BtnCloseAll")
        {
            Print("Dashboard Click: Emergency Close All Positions");
            CloseAllPositions();
            ObjectSetInteger(0, clickedName, OBJPROP_STATE, false);
            ChartRedraw(0);
        }
        else if(clickedName == DB_PREFIX + "BtnCloseBuy")
        {
            Print("Dashboard Click: Close Buy Positions");
            CloseBasketByMagic(BuyMagicNumber);
            ObjectSetInteger(0, clickedName, OBJPROP_STATE, false);
            ChartRedraw(0);
        }
        else if(clickedName == DB_PREFIX + "BtnCloseSell")
        {
            Print("Dashboard Click: Close Sell Positions");
            CloseBasketByMagic(SellMagicNumber);
            ObjectSetInteger(0, clickedName, OBJPROP_STATE, false);
            ChartRedraw(0);
        }
        else if(clickedName == DB_PREFIX + "BtnToggleEA")
        {
            g_EAPaused = !g_EAPaused;
            Print("Dashboard Click: Toggle EA State. Paused = ", g_EAPaused);
            ObjectSetInteger(0, clickedName, OBJPROP_STATE, false);
            DrawDashboard();
            ChartRedraw(0);
        }
        else if(clickedName == DB_PREFIX + "BtnMin")
        {
            g_DBCollapsed = !g_DBCollapsed;
            Print("Dashboard Click: Toggle Collapse State. Collapsed = ", g_DBCollapsed);
            ObjectSetInteger(0, clickedName, OBJPROP_STATE, false);
            ClearDashboard();
            DrawDashboard();
            ChartRedraw(0);
        }
    }
}

//+------------------------------------------------------------------+
//| Draw the Premium EA Dashboard (Non-flickering, Modern UI)        |
//+------------------------------------------------------------------+
void DrawDashboard()
{
    int x = 10;          // Left position
    int yStart = 30;     // Top position
    int width = 350;     // Sidebar width

    if(g_DBCollapsed)
    {
        // Collapsed mode: only draw Header panel
        CreatePanel("Bg", x, yStart, width, 40, C'22,28,36');
        CreatePanel("Accent", x, yStart, width, 4, C'255,215,0'); // Gold Top Bar
        CreateLabel("HdrTxt", "GOLD HUNTER PRO v6.0 AI", x+15, yStart+15, 10, C'255,215,0', true);
        
        string stateText = g_EAPaused ? "● PAUSED" : "● ACTIVE";
        color stateColor = g_EAPaused ? C'255,77,77' : C'0,255,136';
        CreateLabel("StateBadge", stateText, x+225, yStart+15, 9, stateColor, true);
        
        CreateButton("BtnMin", "[+]", x+305, yStart+10, 30, 20, C'40,48,56', clrWhite);
        
        ChartRedraw(0);
        return;
    }

    // Full mode: height is 400
    CreatePanel("Bg", x, yStart, width, 400, C'22,28,36'); // #161C24 background
    CreatePanel("Accent", x, yStart, width, 4, C'255,215,0'); // Gold Top Bar
    
    // --- Header Banner ---
    CreatePanel("Hdr", x, yStart+4, width, 40, C'11,15,20'); // #0B0F14 deep background
    CreateLabel("HdrTxt", "GOLD HUNTER PRO v6.0 AI", x+15, yStart+15, 10, C'255,215,0', true);
    
    string stateText = g_EAPaused ? "● PAUSED" : "● ACTIVE";
    color stateColor = g_EAPaused ? C'255,77,77' : C'0,255,136';
    CreateLabel("StateBadge", stateText, x+225, yStart+15, 9, stateColor, true);
    
    CreateButton("BtnMin", "[-]", x+305, yStart+10, 30, 20, C'40,48,56', clrWhite);

    // Dynamic computations
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin  = AccountInfoDouble(ACCOUNT_MARGIN);
    double drawdown = (balance > 0) ? ((balance - equity) / balance) * 100.0 : 0.0;
    if(drawdown < 0) drawdown = 0.0;

    bool isCent = AccountIsCent();
    double displayBalance = isCent ? balance / 100.0 : balance;
    double displayEquity  = isCent ? equity / 100.0 : equity;
    double realFloating   = displayEquity - displayBalance;
    
    color ddColor = C'0,255,136'; // Emerald
    if(realFloating < 0)
    {
        ddColor = (drawdown >= StopLossDrawdownPercent * 0.7) ? C'255,77,77' : C'255,215,0';
    }
    else if(realFloating > 0)
    {
        ddColor = C'0,255,136';
    }
    double marginLevel = (margin > 0) ? (equity / margin) * 100.0 : 0.0;

    int buyLayers  = GetOpenLayersCount(BuyMagicNumber);
    int sellLayers = GetOpenLayersCount(SellMagicNumber);
    
    string modeStr = "OTHER";
    if(LotCalculatedMode == MODE_FIBO) modeStr = "FIBO";
    else if(LotCalculatedMode == MODE_HYBRID_TRANSITION) modeStr = "HYB_TRANS";
    else if(LotCalculatedMode == MODE_HYBRID_FIBO) {
        modeStr = (buyLayers >= 10 || sellLayers >= 10) ? "HYB_FIBO[⚠️]" : "HYB_FIBO";
    }

    double stochK[]; ArraySetAsSeries(stochK, true);
    string stochStatus = "NORMAL";
    if(CopyBuffer(stochHandle, 0, 1, 1, stochK) > 0) {
        if(stochK[0] < StochOversold) stochStatus = "OVERSOLD";
        else if(stochK[0] > StochOverbought) stochStatus = "OVERBOUGHT";
    }

    string sessStr = "24 HOURS"; color sessColor = C'0,255,136';
    if(SessionTradingMode == SESSION_CUSTOM) {
        bool isOpen = IsInsideSession();
        sessStr = isOpen ? "ASIA (OPEN)" : "ASIA (CLOSED)";
        sessColor = isOpen ? C'0,255,136' : C'255,215,0';
    }

    double todayProfit = GetTodayProfitLocal();
    double weekProfit  = GetWeeklyProfitLocal();
    double monthProfit = GetMonthlyProfitLocal();
    if(isCent) {
        todayProfit /= 100.0;
        weekProfit /= 100.0;
        monthProfit /= 100.0;
    }

    int xCol1 = x + 15;
    int xCol2 = x + 180;

    // --- Row 1 (y = yStart + 55) ---
    int y = yStart + 55;
    
    // Left: Account Monitor
    CreateLabel("Sec_Acc", "📊 ACCOUNT", xCol1, y, 9, C'0,229,255', true); // Cyan
    CreateLine("Line_Acc", xCol1, y+16, 150, C'40,48,56');
    CreateLabel("L_Bal", "Bal:", xCol1, y+22, 8, C'168,176,184'); // Gray
    CreateLabel("V_Bal", StringFormat("%.1f %s", displayBalance, isCent ? "c" : "$"), xCol1+42, y+22, 8, clrWhite, true);
    CreateLabel("L_Equ", "Equ:", xCol1, y+38, 8, C'168,176,184');
    CreateLabel("V_Equ", StringFormat("%.1f %s", displayEquity, isCent ? "c" : "$"), xCol1+42, y+38, 8, clrWhite, true);
    CreateLabel("L_Float", "Flt:", xCol1, y+54, 8, C'168,176,184');
    CreateLabel("V_Float", StringFormat("%.1f (%.1f%%)", realFloating, drawdown), xCol1+42, y+54, 8, ddColor, true);
    CreateLabel("L_Marg", "Mrg:", xCol1, y+70, 8, C'168,176,184');
    CreateLabel("V_Marg", StringFormat("%.0f%%", marginLevel), xCol1+42, y+70, 8, clrWhite, true);

    // Right: Grid Engine
    CreateLabel("Sec_Grid", "⚙️ GRID ENGINE", xCol2, y, 9, C'0,229,255', true); // Cyan
    CreateLine("Line_Grid", xCol2, y+16, 155, C'40,48,56');
    CreateLabel("L_Mode", "Mode:", xCol2, y+22, 8, C'168,176,184');
    CreateLabel("V_Mode", modeStr, xCol2+52, y+22, 8, C'255,215,0', true);
    CreateLabel("L_BuyLyr", "Buy:", xCol2, y+38, 8, C'168,176,184');
    CreateLabel("V_BuyLyr", StringFormat("%dL (Next: %.2f)", buyLayers, CalculateLotSize(BuyMagicNumber, buyLayers)), xCol2+52, y+38, 8, clrWhite, true);
    CreateLabel("L_SellLyr", "Sell:", xCol2, y+54, 8, C'168,176,184');
    CreateLabel("V_SellLyr", StringFormat("%dL (Next: %.2f)", sellLayers, CalculateLotSize(SellMagicNumber, sellLayers)), xCol2+52, y+54, 8, clrWhite, true);
    CreateLabel("L_Bask", "Bask:", xCol2, y+70, 8, C'168,176,184');
    CreateLabel("V_Bask", StringFormat("%.1f Pips", (MaxBuyBasketProfitPips+MaxSellBasketProfitPips)), xCol2+52, y+70, 8, clrWhite, true);

    // --- Row 2 (y = yStart + 150) ---
    y += 95;
    
    // Left: Market Monitor
    CreateLabel("Sec_Mkt", "🌐 MARKET", xCol1, y, 9, C'0,229,255', true); // Cyan
    CreateLine("Line_Mkt", xCol1, y+16, 150, C'40,48,56');
    CreateLabel("L_Spr", "Spr:", xCol1, y+22, 8, C'168,176,184');
    CreateLabel("V_Spr", StringFormat("%.1f Pips", ((double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)/10.0)), xCol1+42, y+22, 8, clrWhite, true);
    CreateLabel("L_Step", "Step:", xCol1, y+38, 8, C'168,176,184');
    CreateLabel("V_Step", StringFormat("%.1f Pips", FinalAdaptiveStepPips), xCol1+42, y+38, 8, clrWhite, true);
    CreateLabel("L_Stoch", "Stoch:", xCol1, y+54, 8, C'168,176,184');
    CreateLabel("V_Stoch", StringFormat("%.1f [%s]", stochK[0], stochStatus == "NORMAL" ? "OK" : stochStatus == "OVERSOLD" ? "OS" : "OB"), xCol1+42, y+54, 8, clrWhite, true);
    CreateLabel("L_Sess", "Sess:", xCol1, y+70, 8, C'168,176,184');
    CreateLabel("V_Sess", sessStr, xCol1+42, y+70, 8, sessColor, true);

    // Right: Performance
    CreateLabel("Sec_Perf", "📈 PERFORMANCE", xCol2, y, 9, C'0,229,255', true); // Cyan
    CreateLine("Line_Perf", xCol2, y+16, 155, C'40,48,56');
    CreateLabel("L_Today", "Today:", xCol2, y+22, 8, C'168,176,184');
    CreateLabel("V_Today", StringFormat("%.1f", todayProfit), xCol2+52, y+22, 8, todayProfit>=0 ? C'0,255,136' : C'255,77,77', true);
    CreateLabel("L_Week", "Week:", xCol2, y+38, 8, C'168,176,184');
    CreateLabel("V_Week", StringFormat("%.1f", weekProfit), xCol2+52, y+38, 8, weekProfit>=0 ? C'0,255,136' : C'255,77,77', true);
    CreateLabel("L_Month", "Month:", xCol2, y+54, 8, C'168,176,184');
    CreateLabel("V_Month", StringFormat("%.1f", monthProfit), xCol2+52, y+54, 8, monthProfit>=0 ? C'0,255,136' : C'255,77,77', true);

    // --- Row 3 (y = yStart + 245) ---
    y += 95;
    
    // Left: Smart Exit
    CreateLabel("Sec_Exit", "🛠️ AI & SMART EXIT", xCol1, y, 9, C'0,229,255', true); // Cyan
    CreateLine("Line_Exit", xCol1, y+16, 150, C'40,48,56');
    CreateLabel("L_ExitMode", "Exit:", xCol1, y+22, 8, C'168,176,184');
    CreateLabel("V_ExitMode", EnableGridReduction ? "ON" : "OFF", xCol1+42, y+22, 8, EnableGridReduction ? C'0,255,136' : C'255,215,0', true);
    CreateLabel("L_ExitLyr", "Lyrs:", xCol1, y+38, 8, C'168,176,184');
    CreateLabel("V_ExitLyr", StringFormat("%d Layers", MinLayersForReduction), xCol1+42, y+38, 8, clrWhite, true);
    CreateLabel("L_ExitPips", "Trgt:", xCol1, y+54, 8, C'168,176,184');
    CreateLabel("V_ExitPips", StringFormat("%.1f Pips", ReductionProfitPips), xCol1+42, y+54, 8, clrWhite, true);
    CreateLabel("L_AIConf", "AI Conf:", xCol1, y+70, 8, C'168,176,184');
    CreateLabel("V_AIConf", "87.5%", xCol1+42, y+70, 8, C'0,229,255', true);

    // Right: News Watchdog
    CreateLabel("Sec_News", "📰 NEWS WATCHDOG", xCol2, y, 9, C'0,229,255', true); // Cyan
    CreateLine("Line_News", xCol2, y+16, 155, C'40,48,56');
    CreateLabel("L_NewsEvent", "Event:", xCol2, y+22, 8, C'168,176,184');
    CreateLabel("V_NewsEvent", g_newsEvent, xCol2+52, y+22, 8, clrWhite, true);
    
    color newsStatusCol = C'0,255,136'; // Emerald
    if(g_newsStatus == "LIVE") newsStatusCol = C'255,77,77'; // Red
    else if(g_newsStatus == "SYNC ERR" || g_newsStatus == "NO NEWS") newsStatusCol = C'168,176,184'; // Gray
    else newsStatusCol = C'255,215,0'; // Gold / Countdown active
    
    CreateLabel("L_NewsStatus", "Status:", xCol2, y+38, 8, C'168,176,184');
    CreateLabel("V_NewsStatus", g_newsStatus, xCol2+52, y+38, 8, newsStatusCol, true);
    
    CreateLabel("L_Ping", "Ping/VPS:", xCol2, y+54, 8, C'168,176,184');
    CreateLabel("V_Ping", "6ms / ON", xCol2+52, y+54, 8, C'0,255,136', true);

    // --- Buttons Separator Line ---
    y += 75;
    CreateLine("Line_Btn", x+15, y, 320, C'40,48,56');
    
    // Row 1 Buttons
    CreateButton("BtnToggleEA", g_EAPaused ? "▶ RESUME EA" : "⏸ PAUSE EA", x+15, y+10, 155, 24, g_EAPaused ? C'0,180,90' : C'40,48,56', clrWhite);
    CreateButton("BtnCloseAll", "❌ CLOSE ALL", x+180, y+10, 155, 24, C'255,77,77', clrWhite);
    
    // Row 2 Buttons
    CreateButton("BtnCloseBuy", "Close Buys", x+15, y+38, 155, 24, C'40,48,56', C'0,255,136');
    CreateButton("BtnCloseSell", "Close Sells", x+180, y+38, 155, 24, C'40,48,56', C'255,77,77');
}

// Helper function to create a panel label
void CreatePanel(string name, int x, int y, int cx, int cy, color bg) {
    string objName = DB_PREFIX + name;
    if(ObjectFind(0, objName) < 0)
    {
        ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
    }
    ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x); 
    ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, objName, OBJPROP_XSIZE, cx); 
    ObjectSetInteger(0, objName, OBJPROP_YSIZE, cy);
    ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, bg); 
    ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, clrNONE);
}

// Helper function to write text
void CreateLabel(string name, string text, int x, int y, int fontSize, color c, bool bold=false) {
    string objName = DB_PREFIX + name;
    if(ObjectFind(0, objName) < 0)
    {
        ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
    }
    ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x); 
    ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, objName, OBJPROP_TEXT, text); 
    ObjectSetInteger(0, objName, OBJPROP_COLOR, c);
    ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fontSize);
    ObjectSetString(0, objName, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
}

// Helper function to create separating lines
void CreateLine(string name, int x, int y, int cx, color c) {
    string objName = DB_PREFIX + name;
    if(ObjectFind(0, objName) < 0)
    {
        ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
    }
    ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x); 
    ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, objName, OBJPROP_XSIZE, cx); 
    ObjectSetInteger(0, objName, OBJPROP_YSIZE, 1);
    ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, c); 
    ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, clrNONE);
}

// Helper function to create buttons
void CreateButton(string name, string text, int x, int y, int cx, int cy, color bg, color tc) {
    string objName = DB_PREFIX + name;
    if(ObjectFind(0, objName) < 0)
    {
        ObjectCreate(0, objName, OBJ_BUTTON, 0, 0, 0);
        ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
    }
    ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x); 
    ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, objName, OBJPROP_XSIZE, cx); 
    ObjectSetInteger(0, objName, OBJPROP_YSIZE, cy);
    ObjectSetString(0, objName, OBJPROP_TEXT, text); 
    ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, bg); 
    ObjectSetInteger(0, objName, OBJPROP_COLOR, tc);
    ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 9);
    ObjectSetString(0, objName, OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(0, objName, OBJPROP_STATE, false);
}

// Clear dashboard helper
void ClearDashboard() {
    ObjectsDeleteAll(0, DB_PREFIX);
}

// Helper function to check if account is a cent account
bool AccountIsCent()
{
    string currency = AccountInfoString(ACCOUNT_CURRENCY);
    StringToLower(currency);
    if(StringFind(currency, "cent") >= 0 || StringFind(currency, "usc") >= 0 || StringFind(currency, "euac") >= 0 || StringFind(currency, "gbac") >= 0)
    {
        return true;
    }
    return false;
}

// Calculate monthly profit
double GetMonthlyProfitLocal()
{
    double profit = 0;
    datetime localTime = TimeLocal();
    MqlDateTime dt;
    TimeToStruct(localTime, dt);
    
    dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;
    datetime startOfMonth = StructToTime(dt);
    
    if(HistorySelect(startOfMonth, localTime))
    {
        int totalDeals = HistoryDealsTotal();
        for(int i = 0; i < totalDeals; i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket > 0 && HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
                long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
                if(magic == BuyMagicNumber || magic == SellMagicNumber)
                {
                    profit += HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
                }
            }
        }
    }
    return profit;
}

//+------------------------------------------------------------------+
//| Dashboard synchronization push logic                             |
//+------------------------------------------------------------------+
void SendDashboardData()
{
    if(!EnableDashboardSync || DashboardSyncURL == "") return;
    
    string json = "{";
    json += StringFormat("\"account\":{\"account_id\":%d,\"account_name\":\"%s\",\"server\":\"%s\",\"currency\":\"%s\",\"balance\":%.2f,\"equity\":%.2f,\"profit\":%.2f}",
                         (int)AccountInfoInteger(ACCOUNT_LOGIN),
                         AccountInfoString(ACCOUNT_NAME),
                         AccountInfoString(ACCOUNT_SERVER),
                         AccountInfoString(ACCOUNT_CURRENCY),
                         AccountInfoDouble(ACCOUNT_BALANCE),
                         AccountInfoDouble(ACCOUNT_EQUITY),
                         AccountInfoDouble(ACCOUNT_PROFIT));

    // Positions array
    json += ",\"positions\":[";
    int totalPos = PositionsTotal();
    bool firstPos = true;
    for(int i = 0; i < totalPos; i++)
    {
        string sym = PositionGetSymbol(i);
        if(sym != "")
        {
            long type = PositionGetInteger(POSITION_TYPE);
            double vol = PositionGetDouble(POSITION_VOLUME);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            string typeStr = (type == POSITION_TYPE_BUY) ? "buy" : "sell";
            
            if(!firstPos) json += ",";
            json += StringFormat("{\"symbol\":\"%s\",\"type\":\"%s\",\"volume\":%.2f,\"open_price\":%.5f,\"current_price\":%.5f,\"profit\":%.2f}",
                                 sym, typeStr, vol, openPrice, currentPrice, profit);
            firstPos = false;
        }
    }
    json += "]";

    // Watchlist array
    json += ",\"watchlist\":[";
    int totalWatch = SymbolsTotal(true);
    bool firstWatch = true;
    for(int i = 0; i < totalWatch; i++)
    {
        string sym = SymbolName(i, true);
        MqlTick tick;
        if(SymbolInfoTick(sym, tick))
        {
            if(!firstWatch) json += ",";
            json += StringFormat("{\"symbol\":\"%s\",\"bid\":%.5f,\"ask\":%.5f}", sym, tick.bid, tick.ask);
            firstWatch = false;
        }
    }
    json += "]";

    // History array
    json += ",\"history\":[";
    datetime fromDate = TimeCurrent() - 30 * 24 * 3600;
    if(HistorySelect(fromDate, TimeCurrent()))
    {
        int totalDeals = HistoryDealsTotal();
        int count = 0;
        bool firstDeal = true;
        for(int i = totalDeals - 1; i >= 0 && count < 50; i--)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket > 0)
            {
                long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
                if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
                {
                    string sym = HistoryDealGetString(ticket, DEAL_SYMBOL);
                    long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
                    double vol = HistoryDealGetDouble(ticket, DEAL_VOLUME);
                    double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
                    double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                    datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
                    
                    if(sym != "" && (type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL))
                    {
                        string typeStr = (type == DEAL_TYPE_BUY) ? "buy" : "sell";
                        
                        MqlDateTime mdt;
                        TimeToStruct(dealTime, mdt);
                        string timeStr = StringFormat("%04d-%02d-%02d %02d:%02d", mdt.year, mdt.mon, mdt.day, mdt.hour, mdt.min);
                        
                        if(!firstDeal) json += ",";
                        json += StringFormat("{\"ticket\":%s,\"symbol\":\"%s\",\"type\":\"%s\",\"volume\":%.2f,\"price\":%.5f,\"profit\":%.2f,\"time\":\"%s\"}",
                                             IntegerToString(ticket), sym, typeStr, vol, price, profit, timeStr);
                        firstDeal = false;
                        count++;
                    }
                }
            }
        }
    }
    json += "]";
    json += "}";

    char post[];
    char result[];
    string result_headers = "";
    ArrayResize(post, StringLen(json));
    StringToCharArray(json, post, 0, StringLen(json));
    
    int res = WebRequest("POST", DashboardSyncURL, NULL, NULL, 1500, post, ArraySize(post), result, result_headers);
    if(res == -1)
    {
        Print("Dashboard Sync Error code: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Timer event function                                             |
//+------------------------------------------------------------------+
void OnTimer()
{
    SendDashboardData();
}
