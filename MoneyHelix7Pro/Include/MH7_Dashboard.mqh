//+------------------------------------------------------------------+
//|  MONEYHELIX7 PRO - Dashboard Visual en MT5                     |
//|  MH7_Dashboard.mqh  v1.0 FINAL                                 |
//|  Panel de control en tiempo real para las 15 instancias        |
//+------------------------------------------------------------------+
#ifndef MH7_DASHBOARD_MQH
#define MH7_DASHBOARD_MQH
#include "MH7_Structures.mqh"
#include "MH7_Performance.mqh"

// ---- Constantes del panel ----
#define DASH_PREFIX   "MH7_DASH_"
#define DASH_X        10
#define DASH_Y        30
#define DASH_W        420
#define DASH_ROW_H    16
#define DASH_FONT     "Courier New"
#define DASH_SIZE     8

//+------------------------------------------------------------------+
//| Crear etiqueta de texto en el grafico                            |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text,
                 color clr = clrWhite, int font_size = 8)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetString(0,  name, OBJPROP_FONT,      DASH_FONT);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  font_size);
      ObjectSetInteger(0, name, OBJPROP_BACK,      false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Crear rectangulo de fondo                                        |
//+------------------------------------------------------------------+
void CreateBackground(string name, int x, int y, int w, int h, color bg_clr)
{
   if(ObjectFind(0, name) >= 0) return;
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bg_clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clrDimGray);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Calcular altura total del panel                                  |
//+------------------------------------------------------------------+
int DashboardHeight(int num_symbols) { return 55 + num_symbols * DASH_ROW_H + 20; }

//+------------------------------------------------------------------+
//| Inicializar dashboard (llamar en OnInit)                         |
//+------------------------------------------------------------------+
void InitDashboard(const SymbolConfig &cfg[], int n)
{
   int total_h = DashboardHeight(n);

   // Fondo principal
   CreateBackground(DASH_PREFIX + "BG", DASH_X - 5, DASH_Y - 5,
                    DASH_W, total_h, C'10,10,30');

   // Titulo
   CreateLabel(DASH_PREFIX + "TITLE", DASH_X, DASH_Y,
               "== MONEYHELIX7 PRO == v1.0 ==", clrGold, 10);

   // Encabezados de columnas
   int hy = DASH_Y + 22;
   CreateLabel(DASH_PREFIX + "HDR",  DASH_X, hy,
               StringFormat("%-10s %-5s %-6s %-6s %-7s %-8s %-6s",
                            "Symbol","Dir","WR%","PF","DD%","PnL$","Str"),
               clrCyan, DASH_SIZE);

   // Linea separadora
   CreateLabel(DASH_PREFIX + "SEP", DASH_X, hy + DASH_ROW_H,
               "-----------------------------------------------------------",
               clrDimGray, DASH_SIZE);
}

//+------------------------------------------------------------------+
//| Actualizar fila de un simbolo en el dashboard                   |
//+------------------------------------------------------------------+
void UpdateDashboardRow(int idx,
                         const SymbolConfig &cfg,
                         const PositionState &pos,
                         const PerformanceMetrics &m,
                         const SignalState &sig)
{
   int y = DASH_Y + 55 + idx * DASH_ROW_H;

   // Direccion actual
   string dir_str = "---";
   color  dir_clr = clrGray;
   if(pos.is_open)
   {
      dir_str = (pos.direction == +1) ? " BUY" : "SELL";
      dir_clr = (pos.direction == +1) ? clrLime : clrTomato;
   }
   else if(sig.direction == +1) { dir_str = "(b)"; dir_clr = clrDarkGreen; }
   else if(sig.direction == -1) { dir_str = "(s)"; dir_clr = clrDarkRed;   }

   // Color de profit
   color pnl_clr = (m.total_profit >= 0) ? clrLime : clrTomato;

   // DD color
   color dd_clr = clrWhite;
   if(m.max_drawdown_pct > 15.0) dd_clr = clrTomato;
   else if(m.max_drawdown_pct > 10.0) dd_clr = clrOrange;

   string row = StringFormat("%-10s %-5s %-6.1f %-6.2f %-7.1f %-8.2f %-3d",
                              cfg.symbol_name,
                              dir_str,
                              m.win_rate_pct,
                              m.profit_factor,
                              m.max_drawdown_pct,
                              m.total_profit,
                              m.consecutive_losses);

   string lbl_name = DASH_PREFIX + "ROW_" + IntegerToString(idx);
   CreateLabel(lbl_name, DASH_X, y, row, clrWhite, DASH_SIZE);

   // Colorear segun estado
   ObjectSetInteger(0, lbl_name, OBJPROP_COLOR,
                    m.total_profit >= 0 ? clrWhite : clrTomato);
}

//+------------------------------------------------------------------+
//| Actualizar seccion de estado global                              |
//+------------------------------------------------------------------+
void UpdateSystemStatus(const SystemState &sys,
                         int n_symbols,
                         double total_pnl)
{
   int y = DASH_Y + 55 + n_symbols * DASH_ROW_H + 8;

   string status = sys.circuit_breaker_active ? "CIRCUIT BREAKER ACTIVE" :
                   sys.is_trading_allowed      ? "SYSTEM: ACTIVE" : "SYSTEM: PAUSED";
   color  sc     = sys.circuit_breaker_active ? clrRed :
                   sys.is_trading_allowed      ? clrLime : clrOrange;

   CreateLabel(DASH_PREFIX + "STATUS", DASH_X, y, status, sc, DASH_SIZE);

   string pnl_str = StringFormat("  |  Total PnL: $%.2f  |  Positions: %d",
                                  total_pnl, sys.total_active_positions);
   CreateLabel(DASH_PREFIX + "PNL", DASH_X + 150, y, pnl_str,
               total_pnl >= 0 ? clrLime : clrTomato, DASH_SIZE);

   // Timestamp
   CreateLabel(DASH_PREFIX + "TIME", DASH_X + 300, y,
               TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
               clrDimGray, DASH_SIZE);
}

//+------------------------------------------------------------------+
//| Actualizar dashboard completo (llamar en cada tick / 15 seg)    |
//+------------------------------------------------------------------+
void UpdateDashboard(const SymbolConfig &cfg[],
                      const PositionState &pos[],
                      const PerformanceMetrics &metrics[],
                      const SignalState &signals[],
                      const SystemState &sys,
                      int n)
{
   double total_pnl = 0;
   for(int i = 0; i < n; i++)
   {
      UpdateDashboardRow(i, cfg[i], pos[i], metrics[i], signals[i]);
      total_pnl += metrics[i].total_profit;
   }
   UpdateSystemStatus(sys, n, total_pnl);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Limpiar todos los objetos del dashboard                          |
//+------------------------------------------------------------------+
void DestroyDashboard()
{
   ObjectsDeleteAll(0, DASH_PREFIX);
   ChartRedraw(0);
}

#endif // MH7_DASHBOARD_MQH
