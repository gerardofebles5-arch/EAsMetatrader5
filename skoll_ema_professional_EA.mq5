//+------------------------------------------------------------------+
//|                                         skoll_ema_professional_EA.mq5 |
//|                           Skoll Trading System - Expert Advisor       |
//|                                    Automated Trading with 7 EMAs      |
//+------------------------------------------------------------------+
#property copyright "Skoll Trading System"
#property link      "https://www.skolltrading.com"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- Objetos globales
CTrade trade;
CPositionInfo position;
CAccountInfo account;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Configuración del EA                          |
//+------------------------------------------------------------------+

//--- GESTIÓN DE RIESGO
input group "========== GESTIÓN DE RIESGO =========="
input double   RiskPercentPerTrade  = 1.0;      // Riesgo por operación (% del Equity) 1-1.5%
input double   RiskRewardRatio      = 2.0;      // Ratio Riesgo:Beneficio (1:2 recomendado)
input double   MaxDailyLossPercent  = 3.0;      // Pérdida máxima diaria (% del Equity)
input double   MaxDailyProfitPercent= 6.0;      // Ganancia máxima diaria (% del Equity) - cerrar día
input int      MaxSimultaneousTrades= 3;        // Máximo de operaciones simultáneas
input bool     UseTrailingStop      = true;     // Usar Trailing Stop
input double   TrailingStopPercent  = 50;       // Trailing Stop (% del profit actual)

//--- CONFIGURACIÓN EMAs
input group "========== CONFIGURACIÓN EMAs =========="
input bool     UseEMA5      = true;             // Usar EMA 5 (Disparador)
input bool     UseEMA10     = true;             // Usar EMA 10 (Rápida)
input bool     UseEMA15     = true;             // Usar EMA 15 (Media 1)
input bool     UseEMA20     = true;             // Usar EMA 20 (Media 2)
input bool     UseEMA50     = true;             // Usar EMA 50 (Intermedia) ⭐
input bool     UseEMA150    = true;             // Usar EMA 150 (Tendencia)
input bool     UseEMA200    = true;             // Usar EMA 200 (Institucional) ⭐

//--- CONFIGURACIÓN DE SEÑALES
input group "========== SEÑALES Y FILTROS =========="
input int      SignalStrength       = 2;        // Fuerza mínima de señal (1=★, 2=★★, 3=★★★)
input double   MinMomentumPercent   = 0.2;      // Momentum mínimo requerido (%)
input bool     RequireLongTermConfirm = true;   // Requiere confirmación EMAs 150/200
input bool     TradeOnlyWithTrend   = true;     // Operar solo a favor de tendencia
input int      MinBarsSinceLastSignal = 3;      // Barras mínimas entre señales

//--- HORARIO DE TRADING
input group "========== HORARIO DE TRADING =========="
input bool     UseTradingHours      = false;    // Activar horario de trading
input int      StartHour            = 8;        // Hora de inicio (hora del servidor)
input int      EndHour              = 20;       // Hora de fin (hora del servidor)
input bool     AvoidNewsTime        = true;     // Evitar operar durante noticias
input int      MinutesBeforeNews    = 30;       // Minutos antes de noticia para cerrar
input int      MinutesAfterNews     = 30;       // Minutos después de noticia para reabrir

//--- CONFIGURACIÓN AVANZADA
input group "========== CONFIGURACIÓN AVANZADA =========="
input int      MagicNumber          = 123456;   // Número mágico único del EA
input string   TradeComment         = "SkollEA";// Comentario en operaciones
input int      Slippage             = 10;       // Slippage máximo permitido (puntos)
input bool     CloseOnOppositeSignal= true;     // Cerrar operación en señal contraria
input bool     UsePartialClose      = true;     // Cerrar 50% en 1:1, dejar 50% para objetivo
input double   PartialClosePercent  = 50;       // Porcentaje a cerrar en profit intermedio

//--- VISUALIZACIÓN
input group "========== VISUALIZACIÓN =========="
input bool     ShowPanel            = true;     // Mostrar panel de información
input bool     ShowSignalArrows     = true;     // Mostrar flechas de señales
input bool     SendAlerts           = false;    // Enviar alertas sonoras
input bool     SendPushNotifications= false;    // Enviar notificaciones push
input color    PanelColor           = clrNavy;  // Color del panel
input int      PanelCorner          = 1;        // Esquina del panel (0-3)

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                               |
//+------------------------------------------------------------------+

//--- Handles de indicadores
int handle_ema5, handle_ema10, handle_ema15, handle_ema20;
int handle_ema50, handle_ema150, handle_ema200;

//--- Buffers de EMAs
double ema5[], ema10[], ema15[], ema20[];
double ema50[], ema150[], ema200[];

//--- Variables de control
datetime lastBarTime = 0;
datetime lastSignalTime = 0;
double dailyStartEquity = 0;
double dailyProfit = 0;
double dailyLoss = 0;
int totalTradesToday = 0;
bool tradingAllowed = true;

//--- Variables de operación
struct TradeInfo {
    int ticket;
    double openPrice;
    double stopLoss;
    double takeProfit;
    double riskAmount;
    double targetProfit;
    datetime openTime;
    bool partialClosed;
};

TradeInfo currentTrades[];

//--- Variables de análisis
struct TrendAnalysis {
    bool isAlignedBullish;
    bool isAlignedBearish;
    int strength;
    string description;
    double momentum;
    bool longTermConfirm;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Validar parámetros
    if(RiskPercentPerTrade < 0.1 || RiskPercentPerTrade > 5.0) {
        Print("ERROR: RiskPercentPerTrade debe estar entre 0.1% y 5.0%");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    if(RiskRewardRatio < 1.0 || RiskRewardRatio > 10.0) {
        Print("ERROR: RiskRewardRatio debe estar entre 1.0 y 10.0");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    if(SignalStrength < 1 || SignalStrength > 3) {
        Print("ERROR: SignalStrength debe ser 1, 2 o 3");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    //--- Configurar trade
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(Slippage);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetAsyncMode(false);
    
    //--- Inicializar handles de EMAs
    if(UseEMA5) {
        handle_ema5 = iMA(_Symbol, _Period, 5, 0, MODE_EMA, PRICE_CLOSE);
        if(handle_ema5 == INVALID_HANDLE) {
            Print("ERROR: No se pudo crear handle EMA 5");
            return(INIT_FAILED);
        }
    }
    
    if(UseEMA10) {
        handle_ema10 = iMA(_Symbol, _Period, 10, 0, MODE_EMA, PRICE_CLOSE);
        if(handle_ema10 == INVALID_HANDLE) {
            Print("ERROR: No se pudo crear handle EMA 10");
            return(INIT_FAILED);
        }
    }
    
    if(UseEMA15) {
        handle_ema15 = iMA(_Symbol, _Period, 15, 0, MODE_EMA, PRICE_CLOSE);
        if(handle_ema15 == INVALID_HANDLE) {
            Print("ERROR: No se pudo crear handle EMA 15");
            return(INIT_FAILED);
        }
    }
    
    if(UseEMA20) {
        handle_ema20 = iMA(_Symbol, _Period, 20, 0, MODE_EMA, PRICE_CLOSE);
        if(handle_ema20 == INVALID_HANDLE) {
            Print("ERROR: No se pudo crear handle EMA 20");
            return(INIT_FAILED);
        }
    }
    
    if(UseEMA50) {
        handle_ema50 = iMA(_Symbol, _Period, 50, 0, MODE_EMA, PRICE_CLOSE);
        if(handle_ema50 == INVALID_HANDLE) {
            Print("ERROR: No se pudo crear handle EMA 50");
            return(INIT_FAILED);
        }
    }
    
    if(UseEMA150) {
        handle_ema150 = iMA(_Symbol, _Period, 150, 0, MODE_EMA, PRICE_CLOSE);
        if(handle_ema150 == INVALID_HANDLE) {
            Print("ERROR: No se pudo crear handle EMA 150");
            return(INIT_FAILED);
        }
    }
    
    if(UseEMA200) {
        handle_ema200 = iMA(_Symbol, _Period, 200, 0, MODE_EMA, PRICE_CLOSE);
        if(handle_ema200 == INVALID_HANDLE) {
            Print("ERROR: No se pudo crear handle EMA 200");
            return(INIT_FAILED);
        }
    }
    
    //--- Configurar arrays
    ArraySetAsSeries(ema5, true);
    ArraySetAsSeries(ema10, true);
    ArraySetAsSeries(ema15, true);
    ArraySetAsSeries(ema20, true);
    ArraySetAsSeries(ema50, true);
    ArraySetAsSeries(ema150, true);
    ArraySetAsSeries(ema200, true);
    
    //--- Inicializar equity diario
    dailyStartEquity = account.Equity();
    
    //--- Crear panel de información
    if(ShowPanel) {
        CreateInfoPanel();
    }
    
    //--- Mensaje de inicio
    Print("═══════════════════════════════════════════════════");
    Print("SKOLL EMA PROFESSIONAL EA - INICIADO CORRECTAMENTE");
    Print("═══════════════════════════════════════════════════");
    Print("Símbolo: ", _Symbol);
    Print("Período: ", EnumToString(_Period));
    Print("Riesgo por trade: ", RiskPercentPerTrade, "%");
    Print("Ratio R:R: 1:", RiskRewardRatio);
    Print("Fuerza mínima: ", SignalStrength, " estrellas");
    Print("Equity inicial: $", DoubleToString(dailyStartEquity, 2));
    Print("═══════════════════════════════════════════════════");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Liberar handles
    if(handle_ema5 != INVALID_HANDLE) IndicatorRelease(handle_ema5);
    if(handle_ema10 != INVALID_HANDLE) IndicatorRelease(handle_ema10);
    if(handle_ema15 != INVALID_HANDLE) IndicatorRelease(handle_ema15);
    if(handle_ema20 != INVALID_HANDLE) IndicatorRelease(handle_ema20);
    if(handle_ema50 != INVALID_HANDLE) IndicatorRelease(handle_ema50);
    if(handle_ema150 != INVALID_HANDLE) IndicatorRelease(handle_ema150);
    if(handle_ema200 != INVALID_HANDLE) IndicatorRelease(handle_ema200);
    
    //--- Eliminar objetos gráficos
    DeleteInfoPanel();
    ObjectsDeleteAll(0, "SkollEA_");
    
    //--- Resumen final
    Print("═══════════════════════════════════════════════════");
    Print("SKOLL EMA EA - FINALIZADO");
    Print("Razón: ", GetDeinitReasonText(reason));
    Print("Trades hoy: ", totalTradesToday);
    Print("P&L diario: $", DoubleToString(dailyProfit - dailyLoss, 2));
    Print("═══════════════════════════════════════════════════");
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Verificar nueva barra
    datetime currentBarTime = iTime(_Symbol, _Period, 0);
    bool isNewBar = (currentBarTime != lastBarTime);
    
    if(isNewBar) {
        lastBarTime = currentBarTime;
        
        //--- Actualizar datos
        UpdateDailyStats();
        
        //--- Verificar límites diarios
        if(!CheckDailyLimits()) {
            tradingAllowed = false;
            if(ShowPanel) UpdateInfoPanel();
            return;
        }
        
        //--- Verificar horario de trading
        if(!IsWithinTradingHours()) {
            if(ShowPanel) UpdateInfoPanel();
            return;
        }
        
        tradingAllowed = true;
        
        //--- Copiar datos de EMAs
        if(!UpdateEMABuffers()) {
            Print("ERROR: No se pudieron actualizar los buffers de EMAs");
            return;
        }
        
        //--- Analizar tendencia
        TrendAnalysis trend = AnalyzeTrend();
        
        //--- Gestionar operaciones abiertas
        ManageOpenPositions(trend);
        
        //--- Buscar nuevas señales
        if(CanOpenNewTrade()) {
            CheckForTradingSignals(trend);
        }
        
        //--- Actualizar panel
        if(ShowPanel) {
            UpdateInfoPanel();
        }
    } else {
        //--- Gestión continua (trailing stop, etc.)
        if(UseTrailingStop) {
            UpdateTrailingStops();
        }
    }
}

//+------------------------------------------------------------------+
//| Actualizar estadísticas diarias                                  |
//+------------------------------------------------------------------+
void UpdateDailyStats()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    static int lastDay = -1;
    
    //--- Resetear estadísticas en nuevo día
    if(dt.day != lastDay) {
        lastDay = dt.day;
        dailyStartEquity = account.Equity();
        dailyProfit = 0;
        dailyLoss = 0;
        totalTradesToday = 0;
        tradingAllowed = true;
        
        Print("═══════════════════════════════════════════════════");
        Print("NUEVO DÍA DE TRADING - ", TimeToString(TimeCurrent(), TIME_DATE));
        Print("Equity inicial del día: $", DoubleToString(dailyStartEquity, 2));
        Print("═══════════════════════════════════════════════════");
    }
    
    //--- Calcular P&L diario
    double currentEquity = account.Equity();
    double dailyPL = currentEquity - dailyStartEquity;
    
    if(dailyPL > 0) {
        dailyProfit = dailyPL;
    } else {
        dailyLoss = MathAbs(dailyPL);
    }
}

//+------------------------------------------------------------------+
//| Verificar límites diarios                                        |
//+------------------------------------------------------------------+
bool CheckDailyLimits()
{
    double currentEquity = account.Equity();
    double dailyPLPercent = ((currentEquity - dailyStartEquity) / dailyStartEquity) * 100.0;
    
    //--- Verificar pérdida máxima diaria
    if(dailyPLPercent <= -MaxDailyLossPercent) {
        if(tradingAllowed) {
            Print("⛔ LÍMITE DE PÉRDIDA DIARIA ALCANZADO: ", DoubleToString(dailyPLPercent, 2), "%");
            Print("Trading detenido por hoy. Equity: $", DoubleToString(currentEquity, 2));
            CloseAllPositions("Límite de pérdida diaria alcanzado");
            
            if(SendAlerts) Alert("SKOLL EA: Límite de pérdida diaria alcanzado!");
            if(SendPushNotifications) SendNotification("SKOLL EA: Trading detenido - Pérdida diaria máxima");
        }
        return false;
    }
    
    //--- Verificar ganancia máxima diaria (proteger profits)
    if(dailyPLPercent >= MaxDailyProfitPercent) {
        if(tradingAllowed) {
            Print("🎯 OBJETIVO DIARIO ALCANZADO: ", DoubleToString(dailyPLPercent, 2), "%");
            Print("Trading detenido por hoy. Equity: $", DoubleToString(currentEquity, 2));
            CloseAllPositions("Objetivo diario de ganancia alcanzado");
            
            if(SendAlerts) Alert("SKOLL EA: ¡Objetivo diario alcanzado!");
            if(SendPushNotifications) SendNotification("SKOLL EA: ¡Objetivo diario logrado! +" + DoubleToString(dailyPLPercent, 1) + "%");
        }
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Verificar horario de trading                                     |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    if(!UseTradingHours) return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    if(dt.hour >= StartHour && dt.hour < EndHour) {
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Actualizar buffers de EMAs                                       |
//+------------------------------------------------------------------+
bool UpdateEMABuffers()
{
    if(UseEMA5 && CopyBuffer(handle_ema5, 0, 0, 3, ema5) <= 0) return false;
    if(UseEMA10 && CopyBuffer(handle_ema10, 0, 0, 3, ema10) <= 0) return false;
    if(UseEMA15 && CopyBuffer(handle_ema15, 0, 0, 3, ema15) <= 0) return false;
    if(UseEMA20 && CopyBuffer(handle_ema20, 0, 0, 3, ema20) <= 0) return false;
    if(UseEMA50 && CopyBuffer(handle_ema50, 0, 0, 3, ema50) <= 0) return false;
    if(UseEMA150 && CopyBuffer(handle_ema150, 0, 0, 3, ema150) <= 0) return false;
    if(UseEMA200 && CopyBuffer(handle_ema200, 0, 0, 3, ema200) <= 0) return false;
    
    ArraySetAsSeries(ema5, true);
    ArraySetAsSeries(ema10, true);
    ArraySetAsSeries(ema15, true);
    ArraySetAsSeries(ema20, true);
    ArraySetAsSeries(ema50, true);
    ArraySetAsSeries(ema150, true);
    ArraySetAsSeries(ema200, true);
    
    return true;
}

//+------------------------------------------------------------------+
//| Analizar tendencia según sistema Skoll                           |
//+------------------------------------------------------------------+
TrendAnalysis AnalyzeTrend()
{
    TrendAnalysis result;
    result.isAlignedBullish = false;
    result.isAlignedBearish = false;
    result.strength = 0;
    result.description = "LATERAL";
    result.momentum = 0;
    result.longTermConfirm = false;
    
    //--- Obtener precio actual
    double close = iClose(_Symbol, _Period, 0);
    
    //--- Verificar alineación básica (EMAs cortas)
    bool basicBullish = true;
    bool basicBearish = true;
    
    if(UseEMA5 && UseEMA10) {
        basicBullish = basicBullish && (ema5[0] > ema10[0]);
        basicBearish = basicBearish && (ema5[0] < ema10[0]);
    }
    
    if(UseEMA10 && UseEMA15) {
        basicBullish = basicBullish && (ema10[0] > ema15[0]);
        basicBearish = basicBearish && (ema10[0] < ema15[0]);
    }
    
    if(UseEMA15 && UseEMA20) {
        basicBullish = basicBullish && (ema15[0] > ema20[0]);
        basicBearish = basicBearish && (ema15[0] < ema20[0]);
    }
    
    //--- Verificar alineación media (EMA 50)
    bool mediumBullish = true;
    bool mediumBearish = true;
    
    if(UseEMA20 && UseEMA50) {
        mediumBullish = (ema20[0] > ema50[0]);
        mediumBearish = (ema20[0] < ema50[0]);
    }
    
    //--- Verificar alineación larga (EMAs 150, 200)
    bool longBullish = true;
    bool longBearish = true;
    
    if(UseEMA50 && UseEMA150) {
        longBullish = longBullish && (ema50[0] > ema150[0]);
        longBearish = longBearish && (ema50[0] < ema150[0]);
    }
    
    if(UseEMA150 && UseEMA200) {
        longBullish = longBullish && (ema150[0] > ema200[0]);
        longBearish = longBearish && (ema150[0] < ema200[0]);
    }
    
    //--- Confirmar con precio
    if(UseEMA150) {
        result.longTermConfirm = (close > ema150[0]) || (close < ema150[0]);
    }
    
    if(UseEMA200) {
        result.longTermConfirm = result.longTermConfirm && 
                                ((close > ema200[0]) || (close < ema200[0]));
    }
    
    //--- Determinar fuerza y dirección
    if(basicBullish && mediumBullish && longBullish) {
        result.isAlignedBullish = true;
        result.strength = 3;
        result.description = "ALCISTA FUERTE";
    } else if(basicBullish && mediumBullish) {
        result.isAlignedBullish = true;
        result.strength = 2;
        result.description = "ALCISTA MEDIA";
    } else if(basicBullish) {
        result.isAlignedBullish = true;
        result.strength = 1;
        result.description = "ALCISTA DÉBIL";
    }
    
    if(basicBearish && mediumBearish && longBearish) {
        result.isAlignedBearish = true;
        result.strength = 3;
        result.description = "BAJISTA FUERTE";
    } else if(basicBearish && mediumBearish) {
        result.isAlignedBearish = true;
        result.strength = 2;
        result.description = "BAJISTA MEDIA";
    } else if(basicBearish) {
        result.isAlignedBearish = true;
        result.strength = 1;
        result.description = "BAJISTA DÉBIL";
    }
    
    //--- Calcular momentum
    if(UseEMA5 && UseEMA20) {
        result.momentum = MathAbs(ema5[0] - ema20[0]) / ema20[0] * 100.0;
    } else if(UseEMA10 && UseEMA20) {
        result.momentum = MathAbs(ema10[0] - ema20[0]) / ema20[0] * 100.0;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Verificar si se puede abrir nueva operación                      |
//+------------------------------------------------------------------+
bool CanOpenNewTrade()
{
    if(!tradingAllowed) return false;
    
    //--- Contar operaciones abiertas
    int openPositions = CountOpenPositions();
    if(openPositions >= MaxSimultaneousTrades) {
        return false;
    }
    
    //--- Verificar tiempo desde última señal
    if(TimeCurrent() - lastSignalTime < MinBarsSinceLastSignal * PeriodSeconds(_Period)) {
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Contar operaciones abiertas del EA                               |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(position.SelectByIndex(i)) {
            if(position.Symbol() == _Symbol && position.Magic() == MagicNumber) {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Verificar señales de trading                                     |
//+------------------------------------------------------------------+
void CheckForTradingSignals(TrendAnalysis &trend)
{
    //--- Verificar fuerza mínima
    if(trend.strength < SignalStrength) return;
    
    //--- Verificar momentum mínimo
    if(trend.momentum < MinMomentumPercent) return;
    
    //--- Verificar confirmación de largo plazo si está activada
    if(RequireLongTermConfirm && !trend.longTermConfirm) return;
    
    double close = iClose(_Symbol, _Period, 0);
    double open = iOpen(_Symbol, _Period, 1);
    
    //--- SEÑAL DE COMPRA
    if(trend.isAlignedBullish) {
        //--- Verificar condiciones adicionales
        bool priceCross = (close > ema10[0]);
        bool emaCross = UseEMA5 && UseEMA10 && (ema5[0] > ema10[0]) && (ema5[1] <= ema10[1]);
        
        bool longTermOK = true;
        if(RequireLongTermConfirm) {
            if(UseEMA150) longTermOK = (close > ema150[0]);
            if(UseEMA200) longTermOK = longTermOK && (close > ema200[0]);
        }
        
        if((priceCross || emaCross) && longTermOK) {
            OpenBuyTrade(trend);
        }
    }
    
    //--- SEÑAL DE VENTA
    if(trend.isAlignedBearish) {
        //--- Verificar condiciones adicionales
        bool priceCross = (close < ema10[0]);
        bool emaCross = UseEMA5 && UseEMA10 && (ema5[0] < ema10[0]) && (ema5[1] >= ema10[1]);
        
        bool longTermOK = true;
        if(RequireLongTermConfirm) {
            if(UseEMA150) longTermOK = (close < ema150[0]);
            if(UseEMA200) longTermOK = longTermOK && (close < ema200[0]);
        }
        
        if((priceCross || emaCross) && longTermOK) {
            OpenSellTrade(trend);
        }
    }
}

//+------------------------------------------------------------------+
//| Abrir operación de COMPRA                                        |
//+------------------------------------------------------------------+
void OpenBuyTrade(TrendAnalysis &trend)
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    //--- Calcular Stop Loss y Take Profit basados en riesgo
    double slDistance = CalculateStopLossDistance(true, price);
    double sl = NormalizeDouble(price - slDistance, _Digits);
    double tp = NormalizeDouble(price + (slDistance * RiskRewardRatio), _Digits);
    
    //--- Calcular tamaño de lote basado en riesgo
    double lotSize = CalculateLotSize(slDistance);
    
    if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
        Print("⚠️ Tamaño de lote calculado muy pequeño: ", lotSize);
        return;
    }
    
    //--- Verificar margen disponible
    if(!CheckMarginRequirement(lotSize, ORDER_TYPE_BUY)) {
        Print("⚠️ Margen insuficiente para abrir operación");
        return;
    }
    
    //--- Abrir operación
    string comment = TradeComment + "_BUY_" + IntegerToString(trend.strength) + "★";
    
    if(trade.Buy(lotSize, _Symbol, price, sl, tp, comment)) {
        lastSignalTime = TimeCurrent();
        totalTradesToday++;
        
        Print("═══════════════════════════════════════════════════");
        Print("✅ COMPRA ABIERTA");
        Print("Precio: ", price);
        Print("SL: ", sl, " (", DoubleToString(slDistance / _Point, 0), " pips)");
        Print("TP: ", tp, " (", DoubleToString((tp - price) / _Point, 0), " pips)");
        Print("Lote: ", lotSize);
        Print("Fuerza: ", trend.strength, "★");
        Print("Riesgo: $", DoubleToString(lotSize * slDistance / _Point * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 2));
        Print("═══════════════════════════════════════════════════");
        
        if(ShowSignalArrows) DrawSignalArrow("BUY", iTime(_Symbol, _Period, 0), iLow(_Symbol, _Period, 0));
        if(SendAlerts) Alert("SKOLL EA: Compra abierta en ", _Symbol);
        if(SendPushNotifications) SendNotification("SKOLL EA: COMPRA " + _Symbol + " @ " + DoubleToString(price, _Digits));
    } else {
        Print("❌ ERROR al abrir COMPRA: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Abrir operación de VENTA                                         |
//+------------------------------------------------------------------+
void OpenSellTrade(TrendAnalysis &trend)
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    //--- Calcular Stop Loss y Take Profit basados en riesgo
    double slDistance = CalculateStopLossDistance(false, price);
    double sl = NormalizeDouble(price + slDistance, _Digits);
    double tp = NormalizeDouble(price - (slDistance * RiskRewardRatio), _Digits);
    
    //--- Calcular tamaño de lote basado en riesgo
    double lotSize = CalculateLotSize(slDistance);
    
    if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
        Print("⚠️ Tamaño de lote calculado muy pequeño: ", lotSize);
        return;
    }
    
    //--- Verificar margen disponible
    if(!CheckMarginRequirement(lotSize, ORDER_TYPE_SELL)) {
        Print("⚠️ Margen insuficiente para abrir operación");
        return;
    }
    
    //--- Abrir operación
    string comment = TradeComment + "_SELL_" + IntegerToString(trend.strength) + "★";
    
    if(trade.Sell(lotSize, _Symbol, price, sl, tp, comment)) {
        lastSignalTime = TimeCurrent();
        totalTradesToday++;
        
        Print("═══════════════════════════════════════════════════");
        Print("✅ VENTA ABIERTA");
        Print("Precio: ", price);
        Print("SL: ", sl, " (", DoubleToString(slDistance / _Point, 0), " pips)");
        Print("TP: ", tp, " (", DoubleToString((price - tp) / _Point, 0), " pips)");
        Print("Lote: ", lotSize);
        Print("Fuerza: ", trend.strength, "★");
        Print("Riesgo: $", DoubleToString(lotSize * slDistance / _Point * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 2));
        Print("═══════════════════════════════════════════════════");
        
        if(ShowSignalArrows) DrawSignalArrow("SELL", iTime(_Symbol, _Period, 0), iHigh(_Symbol, _Period, 0));
        if(SendAlerts) Alert("SKOLL EA: Venta abierta en ", _Symbol);
        if(SendPushNotifications) SendNotification("SKOLL EA: VENTA " + _Symbol + " @ " + DoubleToString(price, _Digits));
    } else {
        Print("❌ ERROR al abrir VENTA: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Calcular distancia de Stop Loss                                  |
//+------------------------------------------------------------------+
double CalculateStopLossDistance(bool isBuy, double entryPrice)
{
    //--- Método 1: Basado en EMA 20 o EMA 50
    double slDistance = 0;
    
    if(UseEMA50) {
        slDistance = MathAbs(entryPrice - ema50[0]);
    } else if(UseEMA20) {
        slDistance = MathAbs(entryPrice - ema20[0]);
    } else {
        //--- Método 2: Basado en ATR o porcentaje fijo
        slDistance = entryPrice * (RiskPercentPerTrade / 100.0);
    }
    
    //--- Asegurar distancia mínima (spread + margen)
    double minDistance = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point * 3;
    if(slDistance < minDistance) {
        slDistance = minDistance;
    }
    
    //--- Verificar stop level del broker
    double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    if(slDistance < stopLevel) {
        slDistance = stopLevel * 1.5;
    }
    
    return slDistance;
}

//+------------------------------------------------------------------+
//| Calcular tamaño de lote basado en riesgo                         |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
    double equity = account.Equity();
    double riskAmount = equity * (RiskPercentPerTrade / 100.0);
    
    //--- Calcular valor del tick
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    //--- Calcular pips de riesgo
    double riskPips = slDistance / _Point;
    
    //--- Calcular lote
    double lotSize = riskAmount / (riskPips * tickValue);
    
    //--- Normalizar al step de volumen
    double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    lotSize = MathFloor(lotSize / volumeStep) * volumeStep;
    
    //--- Verificar límites
    double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    if(lotSize < minVolume) lotSize = minVolume;
    if(lotSize > maxVolume) lotSize = maxVolume;
    
    return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Verificar requisitos de margen                                   |
//+------------------------------------------------------------------+
bool CheckMarginRequirement(double lotSize, ENUM_ORDER_TYPE orderType)
{
    double freeMargin = account.FreeMargin();
    double requiredMargin = 0;
    
    if(!OrderCalcMargin(orderType, _Symbol, lotSize, SymbolInfoDouble(_Symbol, SYMBOL_ASK), requiredMargin)) {
        return false;
    }
    
    return (freeMargin > requiredMargin * 1.2); // 20% de margen extra
}

//+------------------------------------------------------------------+
//| Gestionar posiciones abiertas                                    |
//+------------------------------------------------------------------+
void ManageOpenPositions(TrendAnalysis &trend)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(position.SelectByIndex(i)) {
            if(position.Symbol() != _Symbol || position.Magic() != MagicNumber) continue;
            
            ulong ticket = position.Ticket();
            double openPrice = position.PriceOpen();
            double currentPrice = position.PriceCurrent();
            double sl = position.StopLoss();
            double tp = position.TakeProfit();
            ENUM_POSITION_TYPE posType = position.PositionType();
            
            //--- Cerrar en señal contraria
            if(CloseOnOppositeSignal) {
                if(posType == POSITION_TYPE_BUY && trend.isAlignedBearish && trend.strength >= 2) {
                    ClosePosition(ticket, "Señal contraria detectada");
                    continue;
                }
                if(posType == POSITION_TYPE_SELL && trend.isAlignedBullish && trend.strength >= 2) {
                    ClosePosition(ticket, "Señal contraria detectada");
                    continue;
                }
            }
            
            //--- Cierre parcial en 1:1
            if(UsePartialClose) {
                ManagePartialClose(ticket, openPrice, currentPrice, sl, posType);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Gestionar cierre parcial en 1:1                                  |
//+------------------------------------------------------------------+
void ManagePartialClose(ulong ticket, double openPrice, double currentPrice, double sl, ENUM_POSITION_TYPE posType)
{
    double slDistance = MathAbs(openPrice - sl);
    double profitDistance = 0;
    
    if(posType == POSITION_TYPE_BUY) {
        profitDistance = currentPrice - openPrice;
    } else {
        profitDistance = openPrice - currentPrice;
    }
    
    //--- Si alcanzó 1:1, cerrar 50%
    if(profitDistance >= slDistance) {
        if(position.SelectByTicket(ticket)) {
            double currentVolume = position.Volume();
            double closeVolume = NormalizeDouble(currentVolume * (PartialClosePercent / 100.0), 2);
            
            if(closeVolume >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
                if(trade.PositionClosePartial(ticket, closeVolume)) {
                    Print("💰 Cierre parcial ejecutado: ", closeVolume, " lotes en 1:1");
                    
                    //--- Mover SL a breakeven en la posición restante
                    if(trade.PositionModify(ticket, openPrice, position.TakeProfit())) {
                        Print("✅ Stop Loss movido a breakeven");
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Actualizar trailing stops                                        |
//+------------------------------------------------------------------+
void UpdateTrailingStops()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(position.SelectByIndex(i)) {
            if(position.Symbol() != _Symbol || position.Magic() != MagicNumber) continue;
            
            ulong ticket = position.Ticket();
            double openPrice = position.PriceOpen();
            double currentPrice = position.PriceCurrent();
            double sl = position.StopLoss();
            double tp = position.TakeProfit();
            ENUM_POSITION_TYPE posType = position.PositionType();
            
            double profitDistance = 0;
            double newSL = sl;
            
            if(posType == POSITION_TYPE_BUY) {
                profitDistance = currentPrice - openPrice;
                if(profitDistance > 0) {
                    double trailDistance = profitDistance * (TrailingStopPercent / 100.0);
                    newSL = currentPrice - trailDistance;
                    newSL = NormalizeDouble(newSL, _Digits);
                    
                    if(newSL > sl && newSL < currentPrice) {
                        if(trade.PositionModify(ticket, newSL, tp)) {
                            Print("📊 Trailing Stop actualizado (BUY): ", newSL);
                        }
                    }
                }
            } else {
                profitDistance = openPrice - currentPrice;
                if(profitDistance > 0) {
                    double trailDistance = profitDistance * (TrailingStopPercent / 100.0);
                    newSL = currentPrice + trailDistance;
                    newSL = NormalizeDouble(newSL, _Digits);
                    
                    if((sl == 0 || newSL < sl) && newSL > currentPrice) {
                        if(trade.PositionModify(ticket, newSL, tp)) {
                            Print("📊 Trailing Stop actualizado (SELL): ", newSL);
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Cerrar posición específica                                       |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket, string reason)
{
    if(trade.PositionClose(ticket)) {
        Print("🔒 Posición cerrada #", ticket, " - Razón: ", reason);
    }
}

//+------------------------------------------------------------------+
//| Cerrar todas las posiciones                                      |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(position.SelectByIndex(i)) {
            if(position.Symbol() == _Symbol && position.Magic() == MagicNumber) {
                ClosePosition(position.Ticket(), reason);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Crear panel de información                                       |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
    string prefix = "SkollEA_Panel_";
    int x = (PanelCorner == 0 || PanelCorner == 2) ? 10 : 10;
    int y = (PanelCorner == 0 || PanelCorner == 1) ? 20 : 20;
    
    //--- Fondo del panel
    ObjectCreate(0, prefix + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, prefix + "BG", OBJPROP_CORNER, PanelCorner);
    ObjectSetInteger(0, prefix + "BG", OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, prefix + "BG", OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, prefix + "BG", OBJPROP_XSIZE, 280);
    ObjectSetInteger(0, prefix + "BG", OBJPROP_YSIZE, 220);
    ObjectSetInteger(0, prefix + "BG", OBJPROP_BGCOLOR, PanelColor);
    ObjectSetInteger(0, prefix + "BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, prefix + "BG", OBJPROP_COLOR, clrGold);
    ObjectSetInteger(0, prefix + "BG", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, prefix + "BG", OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, prefix + "BG", OBJPROP_BACK, true);
    
    //--- Título
    CreateLabel(prefix + "Title", "SKOLL EA v2.0", x + 10, y + 8, clrGold, 10, PanelCorner);
    CreateLabel(prefix + "Status", "Estado: ACTIVO", x + 10, y + 30, clrLime, 8, PanelCorner);
    
    //--- Información
    CreateLabel(prefix + "Equity", "Equity: $0", x + 10, y + 50, clrWhite, 8, PanelCorner);
    CreateLabel(prefix + "DailyPL", "P&L Diario: $0", x + 10, y + 68, clrWhite, 8, PanelCorner);
    CreateLabel(prefix + "OpenTrades", "Operaciones: 0", x + 10, y + 86, clrWhite, 8, PanelCorner);
    CreateLabel(prefix + "Trend", "Tendencia: ---", x + 10, y + 104, clrWhite, 8, PanelCorner);
    CreateLabel(prefix + "Strength", "Fuerza: ---", x + 10, y + 122, clrWhite, 8, PanelCorner);
    CreateLabel(prefix + "Signal", "Señal: ESPERAR", x + 10, y + 145, clrGray, 9, PanelCorner);
    CreateLabel(prefix + "Trades", "Trades Hoy: 0", x + 10, y + 170, clrWhite, 8, PanelCorner);
    CreateLabel(prefix + "Risk", "Riesgo: " + DoubleToString(RiskPercentPerTrade, 1) + "%", x + 10, y + 188, clrYellow, 8, PanelCorner);
}

//+------------------------------------------------------------------+
//| Crear etiqueta de texto                                          |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int size, int corner)
{
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetString(0, name, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Actualizar panel de información                                  |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
    string prefix = "SkollEA_Panel_";
    
    //--- Estado
    string status = tradingAllowed ? "ACTIVO" : "PAUSADO";
    color statusColor = tradingAllowed ? clrLime : clrRed;
    ObjectSetString(0, prefix + "Status", OBJPROP_TEXT, "Estado: " + status);
    ObjectSetInteger(0, prefix + "Status", OBJPROP_COLOR, statusColor);
    
    //--- Equity
    double equity = account.Equity();
    ObjectSetString(0, prefix + "Equity", OBJPROP_TEXT, "Equity: $" + DoubleToString(equity, 2));
    
    //--- P&L Diario
    double dailyPL = equity - dailyStartEquity;
    color plColor = (dailyPL > 0) ? clrLime : (dailyPL < 0) ? clrRed : clrWhite;
    ObjectSetString(0, prefix + "DailyPL", OBJPROP_TEXT, "P&L Diario: $" + DoubleToString(dailyPL, 2));
    ObjectSetInteger(0, prefix + "DailyPL", OBJPROP_COLOR, plColor);
    
    //--- Operaciones abiertas
    int openPos = CountOpenPositions();
    ObjectSetString(0, prefix + "OpenTrades", OBJPROP_TEXT, "Operaciones: " + IntegerToString(openPos) + "/" + IntegerToString(MaxSimultaneousTrades));
    
    //--- Tendencia
    TrendAnalysis trend = AnalyzeTrend();
    color trendColor = trend.isAlignedBullish ? clrLime : (trend.isAlignedBearish ? clrRed : clrGray);
    ObjectSetString(0, prefix + "Trend", OBJPROP_TEXT, "Tendencia: " + trend.description);
    ObjectSetInteger(0, prefix + "Trend", OBJPROP_COLOR, trendColor);
    
    //--- Fuerza
    string strengthText = "";
    for(int i = 0; i < trend.strength; i++) strengthText += "★";
    ObjectSetString(0, prefix + "Strength", OBJPROP_TEXT, "Fuerza: " + strengthText);
    ObjectSetInteger(0, prefix + "Strength", OBJPROP_COLOR, trendColor);
    
    //--- Señal
    string signalText = "ESPERAR";
    color signalColor = clrGray;
    
    if(trend.isAlignedBullish && trend.strength >= SignalStrength && tradingAllowed) {
        signalText = "COMPRAR ▲";
        signalColor = clrLime;
    } else if(trend.isAlignedBearish && trend.strength >= SignalStrength && tradingAllowed) {
        signalText = "VENDER ▼";
        signalColor = clrRed;
    }
    
    ObjectSetString(0, prefix + "Signal", OBJPROP_TEXT, "Señal: " + signalText);
    ObjectSetInteger(0, prefix + "Signal", OBJPROP_COLOR, signalColor);
    
    //--- Trades hoy
    ObjectSetString(0, prefix + "Trades", OBJPROP_TEXT, "Trades Hoy: " + IntegerToString(totalTradesToday));
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Eliminar panel de información                                    |
//+------------------------------------------------------------------+
void DeleteInfoPanel()
{
    string prefix = "SkollEA_Panel_";
    ObjectDelete(0, prefix + "BG");
    ObjectDelete(0, prefix + "Title");
    ObjectDelete(0, prefix + "Status");
    ObjectDelete(0, prefix + "Equity");
    ObjectDelete(0, prefix + "DailyPL");
    ObjectDelete(0, prefix + "OpenTrades");
    ObjectDelete(0, prefix + "Trend");
    ObjectDelete(0, prefix + "Strength");
    ObjectDelete(0, prefix + "Signal");
    ObjectDelete(0, prefix + "Trades");
    ObjectDelete(0, prefix + "Risk");
}

//+------------------------------------------------------------------+
//| Dibujar flecha de señal                                          |
//+------------------------------------------------------------------+
void DrawSignalArrow(string type, datetime time, double price)
{
    string name = "SkollEA_Arrow_" + IntegerToString(time);
    
    if(type == "BUY") {
        ObjectCreate(0, name, OBJ_ARROW_BUY, 0, time, price);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrLime);
    } else {
        ObjectCreate(0, name, OBJ_ARROW_SELL, 0, time, price);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
    }
    
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| Obtener texto de razón de deinicialización                       |
//+------------------------------------------------------------------+
string GetDeinitReasonText(int reason)
{
    switch(reason) {
        case REASON_PROGRAM: return "EA detenido manualmente";
        case REASON_REMOVE: return "EA removido del gráfico";
        case REASON_RECOMPILE: return "EA recompilado";
        case REASON_CHARTCHANGE: return "Cambio de símbolo/período";
        case REASON_CHARTCLOSE: return "Gráfico cerrado";
        case REASON_PARAMETERS: return "Parámetros modificados";
        case REASON_ACCOUNT: return "Cuenta cambiada";
        default: return "Razón desconocida";
    }
}

//+------------------------------------------------------------------+
