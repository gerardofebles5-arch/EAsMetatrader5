//+------------------------------------------------------------------+
//|  MONEYHELIX7 PRO - Configuracion de 15 Simbolos               |
//|  MH7_SymbolConfig.mqh  v1.0 FINAL                              |
//|  Magic Numbers: 700001-700015                                   |
//|  Capital por instancia: $3,333.33                              |
//+------------------------------------------------------------------+
#ifndef MH7_SYMBOLCONFIG_MQH
#define MH7_SYMBOLCONFIG_MQH
#include "MH7_Structures.mqh"

//+------------------------------------------------------------------+
//| Inicializar array de configuracion de los 15 simbolos           |
//+------------------------------------------------------------------+
void InitSymbolConfigs(SymbolConfig &cfg[])
{
   ArrayResize(cfg, 15);

   // ----------------------------------------------------------------
   // INSTANCIA 0: XAUUSD (Oro) - Magic 700001
   // ----------------------------------------------------------------
   cfg[0].symbol_name               = "XAUUSD";
   cfg[0].magic_number              = 700001;
   cfg[0].allocated_capital         = 3333.33;
   cfg[0].risk_percent              = 1.5;      // 1.5% — mean reversion tiene alta WR
   cfg[0].structure_lookback_bars   = 20;       // Bollinger 20 periodos
   cfg[0].momentum_bars             = 14;       // RSI 14
   cfg[0].min_volatility_atr        = 0.30;     // Mas permisivo — mean reversion funciona en baja vol
   cfg[0].signal_quality_threshold  = 62.0;     // Threshold moderado
   cfg[0].trading_in_ny_session     = true;
   cfg[0].trading_in_eu_session     = true;
   cfg[0].correlation_with_xauusd   = 1.00;
   cfg[0].session_risk_multiplier   = 1.0;
   cfg[0].atr_period                = 14;
   cfg[0].atr_sl_multiplier         = 1.0;      // SL ajustado: mean reversion tiene SL estrecho
   cfg[0].tp_ratio_to_sl            = 2.0;      // TP 2x SL: capturar mas de la reversion
   cfg[0].max_lot_size              = 0.50;

   // ----------------------------------------------------------------
   // INSTANCIA 1: DXY (Indice Dolar) - Magic 700002
   // ----------------------------------------------------------------
   cfg[1].symbol_name               = "DXY";
   cfg[1].magic_number              = 700002;
   cfg[1].allocated_capital         = 3333.33;
   cfg[1].risk_percent              = 2.0;
   cfg[1].structure_lookback_bars   = 20;
   cfg[1].momentum_bars             = 10;
   cfg[1].min_volatility_atr        = 0.30;
   cfg[1].signal_quality_threshold  = 65.0;
   cfg[1].trading_in_ny_session     = true;
   cfg[1].trading_in_eu_session     = false;
   cfg[1].correlation_with_xauusd   = -0.95;
   cfg[1].session_risk_multiplier   = 1.0;
   cfg[1].atr_period                = 20;
   cfg[1].atr_sl_multiplier         = 2.5;
   cfg[1].tp_ratio_to_sl            = 3.0;
   cfg[1].max_lot_size              = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 2: EURUSD - Magic 700003
   // ----------------------------------------------------------------
   cfg[2].symbol_name               = "EURUSD";
   cfg[2].magic_number              = 700003;
   cfg[2].allocated_capital         = 3333.33;
   cfg[2].risk_percent              = 2.0;
   cfg[2].structure_lookback_bars   = 15;
   cfg[2].momentum_bars             = 9;
   cfg[2].min_volatility_atr        = 0.40;
   cfg[2].signal_quality_threshold  = 58.0;
   cfg[2].trading_in_ny_session     = true;
   cfg[2].trading_in_eu_session     = true;
   cfg[2].correlation_with_xauusd   = -0.85;
   cfg[2].session_risk_multiplier   = 1.2;
   cfg[2].atr_period                = 14;
   cfg[2].atr_sl_multiplier         = 2.0;
   cfg[2].tp_ratio_to_sl            = 3.5;
   cfg[2].max_lot_size              = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 3: GBPUSD - Magic 700004
   // ----------------------------------------------------------------
   cfg[3].symbol_name               = "GBPUSD";
   cfg[3].magic_number              = 700004;
   cfg[3].allocated_capital         = 3333.33;
   cfg[3].risk_percent              = 2.0;
   cfg[3].structure_lookback_bars   = 16;
   cfg[3].momentum_bars             = 8;
   cfg[3].min_volatility_atr        = 0.45;
   cfg[3].signal_quality_threshold  = 57.0;
   cfg[3].trading_in_ny_session     = true;
   cfg[3].trading_in_eu_session     = true;
   cfg[3].correlation_with_xauusd   = -0.78;
   cfg[3].session_risk_multiplier   = 1.2;
   cfg[3].atr_period                = 14;
   cfg[3].atr_sl_multiplier         = 2.0;
   cfg[3].tp_ratio_to_sl            = 3.5;
   cfg[3].max_lot_size              = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 4: USDJPY - Magic 700005
   // ----------------------------------------------------------------
   cfg[4].symbol_name               = "USDJPY";
   cfg[4].magic_number              = 700005;
   cfg[4].allocated_capital         = 3333.33;
   cfg[4].risk_percent              = 2.0;
   cfg[4].structure_lookback_bars   = 18;
   cfg[4].momentum_bars             = 10;
   cfg[4].min_volatility_atr        = 0.35;
   cfg[4].signal_quality_threshold  = 62.0;
   cfg[4].trading_in_ny_session     = true;
   cfg[4].trading_in_eu_session     = false;
   cfg[4].correlation_with_xauusd   = -0.72;
   cfg[4].session_risk_multiplier   = 1.0;
   cfg[4].atr_period                = 14;
   cfg[4].atr_sl_multiplier         = 2.5;
   cfg[4].tp_ratio_to_sl            = 3.0;
   cfg[4].max_lot_size              = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 5: XAGUSD (Plata) - Magic 700006
   // ----------------------------------------------------------------
   cfg[5].symbol_name               = "XAGUSD";
   cfg[5].magic_number              = 700006;
   cfg[5].allocated_capital         = 3333.33;
   cfg[5].risk_percent              = 2.0;
   cfg[5].structure_lookback_bars   = 14;
   cfg[5].momentum_bars             = 7;
   cfg[5].min_volatility_atr        = 0.60;
   cfg[5].signal_quality_threshold  = 58.0;
   cfg[5].trading_in_ny_session     = true;
   cfg[5].trading_in_eu_session     = true;
   cfg[5].correlation_with_xauusd   = 0.82;
   cfg[5].session_risk_multiplier   = 1.0;
   cfg[5].atr_period                = 12;
   cfg[5].atr_sl_multiplier         = 2.0;
   cfg[5].tp_ratio_to_sl            = 3.8;
   cfg[5].max_lot_size              = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 6: WTICRUSD (Crude Oil) - Magic 700007
   // ----------------------------------------------------------------
   cfg[6].symbol_name               = "WTICRUSD";
   cfg[6].magic_number              = 700007;
   cfg[6].allocated_capital         = 3333.33;
   cfg[6].risk_percent              = 2.0;
   cfg[6].structure_lookback_bars   = 16;
   cfg[6].momentum_bars             = 9;
   cfg[6].min_volatility_atr        = 0.70;
   cfg[6].signal_quality_threshold  = 55.0;
   cfg[6].trading_in_ny_session     = true;
   cfg[6].trading_in_eu_session     = false;
   cfg[6].correlation_with_xauusd   = 0.65;
   cfg[6].session_risk_multiplier   = 1.0;
   cfg[6].atr_period                = 10;
   cfg[6].atr_sl_multiplier         = 2.0;
   cfg[6].tp_ratio_to_sl            = 3.5;
   cfg[6].max_lot_size              = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 7: NATGAS (Gas Natural) - Magic 700008
   // ----------------------------------------------------------------
   cfg[7].symbol_name               = "NATGAS";
   cfg[7].magic_number              = 700008;
   cfg[7].allocated_capital         = 3333.33;
   cfg[7].risk_percent              = 2.0;
   cfg[7].structure_lookback_bars   = 12;
   cfg[7].momentum_bars             = 6;
   cfg[7].min_volatility_atr        = 1.00;
   cfg[7].signal_quality_threshold  = 50.0;
   cfg[7].trading_in_ny_session     = true;
   cfg[7].trading_in_eu_session     = false;
   cfg[7].correlation_with_xauusd   = 0.45;
   cfg[7].session_risk_multiplier   = 1.0;
   cfg[7].atr_period                = 8;
   cfg[7].atr_sl_multiplier         = 1.5;
   cfg[7].tp_ratio_to_sl            = 4.0;
   cfg[7].max_lot_size              = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 8: SPX (S&P 500) - Magic 700009
   // ----------------------------------------------------------------
   cfg[8].symbol_name               = "SPX";
   cfg[8].magic_number              = 700009;
   cfg[8].allocated_capital         = 3333.33;
   cfg[8].risk_percent              = 2.0;
   cfg[8].structure_lookback_bars   = 10;
   cfg[8].momentum_bars             = 6;
   cfg[8].min_volatility_atr        = 0.70;
   cfg[8].signal_quality_threshold  = 55.0;
   cfg[8].trading_in_ny_session     = true;
   cfg[8].trading_in_eu_session     = false;
   cfg[8].correlation_with_xauusd   = -0.58;
   cfg[8].session_risk_multiplier   = 1.0;
   cfg[8].atr_period                = 10;
   cfg[8].atr_sl_multiplier         = 2.0;
   cfg[8].tp_ratio_to_sl            = 3.5;
   cfg[8].max_lot_size              = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 9: DAX (Alemania 40) - Magic 700010
   // ----------------------------------------------------------------
   cfg[9].symbol_name               = "DAX";
   cfg[9].magic_number              = 700010;
   cfg[9].allocated_capital         = 3333.33;
   cfg[9].risk_percent              = 2.0;
   cfg[9].structure_lookback_bars   = 15;
   cfg[9].momentum_bars             = 8;
   cfg[9].min_volatility_atr        = 0.50;
   cfg[9].signal_quality_threshold  = 58.0;
   cfg[9].trading_in_ny_session     = true;
   cfg[9].trading_in_eu_session     = true;
   cfg[9].correlation_with_xauusd   = -0.52;
   cfg[9].session_risk_multiplier   = 1.2;
   cfg[9].atr_period                = 14;
   cfg[9].atr_sl_multiplier         = 2.0;
   cfg[9].tp_ratio_to_sl            = 3.5;
   cfg[9].max_lot_size              = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 10: FTSE (UK Index) - Magic 700011
   // ----------------------------------------------------------------
   cfg[10].symbol_name              = "FTSE";
   cfg[10].magic_number             = 700011;
   cfg[10].allocated_capital        = 3333.33;
   cfg[10].risk_percent             = 2.0;
   cfg[10].structure_lookback_bars  = 15;
   cfg[10].momentum_bars            = 8;
   cfg[10].min_volatility_atr       = 0.50;
   cfg[10].signal_quality_threshold = 58.0;
   cfg[10].trading_in_ny_session    = true;
   cfg[10].trading_in_eu_session    = true;
   cfg[10].correlation_with_xauusd  = -0.48;
   cfg[10].session_risk_multiplier  = 1.2;
   cfg[10].atr_period               = 14;
   cfg[10].atr_sl_multiplier        = 2.0;
   cfg[10].tp_ratio_to_sl           = 3.5;
   cfg[10].max_lot_size             = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 11: NIKKEI (Japon 225) - Magic 700012
   // ----------------------------------------------------------------
   cfg[11].symbol_name              = "NIKKEI";
   cfg[11].magic_number             = 700012;
   cfg[11].allocated_capital        = 3333.33;
   cfg[11].risk_percent             = 2.0;
   cfg[11].structure_lookback_bars  = 17;
   cfg[11].momentum_bars            = 9;
   cfg[11].min_volatility_atr       = 0.40;
   cfg[11].signal_quality_threshold = 60.0;
   cfg[11].trading_in_ny_session    = true;
   cfg[11].trading_in_eu_session    = false;
   cfg[11].correlation_with_xauusd  = -0.42;
   cfg[11].session_risk_multiplier  = 1.0;
   cfg[11].atr_period               = 14;
   cfg[11].atr_sl_multiplier        = 2.0;
   cfg[11].tp_ratio_to_sl           = 3.5;
   cfg[11].max_lot_size             = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 12: COPPER (Cobre) - Magic 700013
   // ----------------------------------------------------------------
   cfg[12].symbol_name              = "COPPER";
   cfg[12].magic_number             = 700013;
   cfg[12].allocated_capital        = 3333.33;
   cfg[12].risk_percent             = 2.0;
   cfg[12].structure_lookback_bars  = 16;
   cfg[12].momentum_bars            = 8;
   cfg[12].min_volatility_atr       = 0.50;
   cfg[12].signal_quality_threshold = 57.0;
   cfg[12].trading_in_ny_session    = true;
   cfg[12].trading_in_eu_session    = false;
   cfg[12].correlation_with_xauusd  = 0.58;
   cfg[12].session_risk_multiplier  = 1.0;
   cfg[12].atr_period               = 12;
   cfg[12].atr_sl_multiplier        = 2.0;
   cfg[12].tp_ratio_to_sl           = 3.5;
   cfg[12].max_lot_size             = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 13: BTCUSD (Bitcoin) - Magic 700014
   // ----------------------------------------------------------------
   cfg[13].symbol_name              = "BTCUSD";
   cfg[13].magic_number             = 700014;
   cfg[13].allocated_capital        = 3333.33;
   cfg[13].risk_percent             = 2.0;
   cfg[13].structure_lookback_bars  = 12;
   cfg[13].momentum_bars            = 5;
   cfg[13].min_volatility_atr       = 1.50;
   cfg[13].signal_quality_threshold = 55.0;
   cfg[13].trading_in_ny_session    = true;
   cfg[13].trading_in_eu_session    = false;
   cfg[13].correlation_with_xauusd  = -0.35;
   cfg[13].session_risk_multiplier  = 1.0;
   cfg[13].atr_period               = 10;
   cfg[13].atr_sl_multiplier        = 1.5;
   cfg[13].tp_ratio_to_sl           = 4.0;
   cfg[13].max_lot_size             = 5.0;

   // ----------------------------------------------------------------
   // INSTANCIA 14: VIX (Volatility Index) - Magic 700015
   // ----------------------------------------------------------------
   cfg[14].symbol_name              = "VIX";
   cfg[14].magic_number             = 700015;
   cfg[14].allocated_capital        = 3333.33;
   cfg[14].risk_percent             = 2.0;
   cfg[14].structure_lookback_bars  = 8;
   cfg[14].momentum_bars            = 4;
   cfg[14].min_volatility_atr       = 2.00;
   cfg[14].signal_quality_threshold = 50.0;
   cfg[14].trading_in_ny_session    = true;
   cfg[14].trading_in_eu_session    = false;
   cfg[14].correlation_with_xauusd  = 0.55;
   cfg[14].session_risk_multiplier  = 1.0;
   cfg[14].atr_period               = 7;
   cfg[14].atr_sl_multiplier        = 1.0;
   cfg[14].tp_ratio_to_sl           = 5.0;
   cfg[14].max_lot_size             = 5.0;

   // Inicializar todos los handles a INVALID_HANDLE
   // (se asignan en InitSymbolHandles solo para simbolos habilitados)
   for(int i = 0; i < 15; i++)
   {
      cfg[i].h_atr_m15   = INVALID_HANDLE;
      cfg[i].h_rsi_m15   = INVALID_HANDLE;
      cfg[i].h_ma50_m15  = INVALID_HANDLE;
      cfg[i].h_ma200_m15 = INVALID_HANDLE;
      cfg[i].h_ma200_d1  = INVALID_HANDLE;
      cfg[i].h_atr_exec  = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Obtener indice de simbolo en el array                            |
//+------------------------------------------------------------------+
int GetSymbolIndex(const SymbolConfig &cfg[], string symbol)
{
   for(int i = 0; i < ArraySize(cfg); i++)
      if(cfg[i].symbol_name == symbol) return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Inicializar handles de indicadores para un simbolo habilitado   |
//| Llamar en OnInit solo para simbolos activos                     |
//+------------------------------------------------------------------+
bool InitSymbolHandles(SymbolConfig &cfg)
{
   cfg.h_atr_m15   = iATR(cfg.symbol_name, PERIOD_M15, cfg.atr_period);
   cfg.h_rsi_m15   = iRSI(cfg.symbol_name, PERIOD_M15, 14, PRICE_CLOSE);
   cfg.h_ma50_m15  = iMA(cfg.symbol_name,  PERIOD_M15, 50,  0, MODE_SMA, PRICE_CLOSE);
   cfg.h_ma200_m15 = iMA(cfg.symbol_name,  PERIOD_M15, 200, 0, MODE_SMA, PRICE_CLOSE);
   cfg.h_ma200_d1  = iMA(cfg.symbol_name,  PERIOD_D1,  200, 0, MODE_SMA, PRICE_CLOSE);
   cfg.h_atr_exec  = cfg.h_atr_m15;  // Reutilizar el mismo handle

   bool ok = (cfg.h_atr_m15   != INVALID_HANDLE &&
              cfg.h_rsi_m15   != INVALID_HANDLE &&
              cfg.h_ma50_m15  != INVALID_HANDLE &&
              cfg.h_ma200_m15 != INVALID_HANDLE &&
              cfg.h_ma200_d1  != INVALID_HANDLE);

   if(!ok)
      PrintFormat("WARNING: Some indicator handles failed for %s", cfg.symbol_name);
   else
      PrintFormat("  Handles initialized for %s", cfg.symbol_name);

   return ok;
}

//+------------------------------------------------------------------+
//| Liberar handles de indicadores de un simbolo                    |
//+------------------------------------------------------------------+
void ReleaseSymbolHandles(SymbolConfig &cfg)
{
   if(cfg.h_atr_m15   != INVALID_HANDLE) { IndicatorRelease(cfg.h_atr_m15);   cfg.h_atr_m15   = INVALID_HANDLE; }
   if(cfg.h_rsi_m15   != INVALID_HANDLE) { IndicatorRelease(cfg.h_rsi_m15);   cfg.h_rsi_m15   = INVALID_HANDLE; }
   if(cfg.h_ma50_m15  != INVALID_HANDLE) { IndicatorRelease(cfg.h_ma50_m15);  cfg.h_ma50_m15  = INVALID_HANDLE; }
   if(cfg.h_ma200_m15 != INVALID_HANDLE) { IndicatorRelease(cfg.h_ma200_m15); cfg.h_ma200_m15 = INVALID_HANDLE; }
   if(cfg.h_ma200_d1  != INVALID_HANDLE) { IndicatorRelease(cfg.h_ma200_d1);  cfg.h_ma200_d1  = INVALID_HANDLE; }
   // h_atr_exec es alias de h_atr_m15, no liberar dos veces
   cfg.h_atr_exec = INVALID_HANDLE;
}

#endif // MH7_SYMBOLCONFIG_MQH
