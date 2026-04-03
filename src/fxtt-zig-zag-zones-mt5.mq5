//+------------------------------------------------------------------+
//| zig-zag-zones.mq5                                               |
//| Copyright 2026, Carlos Oliveira                                  |
//| https://www.forextradingtools.eu                                 |
//|                                                                  |
//| Fast/slow ZigZag + support/resistance zones indicator.          |
//| Core helpers: zig-zag-zones-core.mqh                           |
//|                                                                  |
//| Each ZigZag line is configured independently and rendered        |
//| through the same reusable line abstraction.                     |
//| Support/resistance zones are rendered as chart rectangles.      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Carlos Oliveira"
#property link      "https://www.forextradingtools.eu"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   2

#property indicator_label1  "Fast ZigZag"
#property indicator_type1   DRAW_COLOR_ZIGZAG
#property indicator_color1  clrLimeGreen,clrTomato
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Slow ZigZag"
#property indicator_type2   DRAW_COLOR_ZIGZAG
#property indicator_color2  clrDeepSkyBlue,clrDarkOrange
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

#include "zig-zag-zones-core.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group "=== Fast ZigZag ==="
input int    InpFastDepth        = 6;                // Depth
input int    InpFastDeviation    = 5;                 // Deviation (pips)
input int    InpFastBackstep     = 3;                 // Backstep
input bool   InpShowFastZZ       = true;              // Show fast ZigZag
input color  InpFastZZUpColor    = clrDodgerBlue;      // Upward segment color
input color  InpFastZZDownColor  = clrDodgerBlue;         // Downward segment color
input int    InpFastZZWidth      = 2;                 // Line width

input group "=== Slow ZigZag ==="
input int    InpSlowDepth        = 12;                // Depth
input int    InpSlowDeviation    = 8;                 // Deviation (pips)
input int    InpSlowBackstep     = 6;                 // Backstep
input bool   InpShowSlowZZ       = true;              // Show slow ZigZag
input color  InpSlowZZUpColor    = clrRed;         // Upward segment color
input color  InpSlowZZDownColor  = clrRed;         // Downward segment color
input int    InpSlowZZWidth      = 2;                 // Line width

input group "=== Support / Resistance Zones ==="
input bool   InpShowZones         = true;              // Show zones
input int    InpZoneLookback      = 300;               // Max candles lookback
input int    InpZoneHeight        = 10;                // Zone height (pips)
input bool   InpUseAtrZoneHeight  = true;              // Use ATR-based dynamic zone height
input int    InpAtrPeriod         = 14;                // ATR period
input double InpAtrMultiplier     = 0.35;              // ATR multiplier for zone height
input int    InpAtrMinZonePips    = 5;                 // ATR min zone height (pips)
input int    InpAtrMaxZonePips    = 120;               // ATR max zone height (pips)
input bool   InpUseDynamicAtrMaxCap = true;            // Dynamic ATR-based max cap
input double InpAtrMaxCapMultiplier = 1.20;            // Max cap = ATR(pips) * multiplier
input bool   InpShowZoneDebugLabel = true;             // Show zone sizing diagnostics label
input bool   InpAutoZoneHeight    = true;              // Auto widen zone height if no zones qualify
input int    InpMaxZoneHeightMult = 6;                 // Max auto widen multiplier
input int    InpMaxZones          = 5;                 // Max zones per side
input int    InpMinSlowZonePivots = 2;                 // Min slow pivots per zone
input bool   InpIncludeFastPivots = false;             // Include fast pivots in zones
input int    InpMinFastZonePivots = 1;                 // Min fast pivots per zone
input bool   InpShowBroken        = false;             // Show broken zones
input bool   InpExtendZones       = true;              // Extend zones to the right
input color  InpResistColor       = C'248,224,224';      // Resistance color
input color  InpSupportColor      = C'207,235,214';      // Support color
input bool   InpFillZones         = true;              // Fill zones
input uchar  InpZoneAlpha         = 45;                // Fill opacity (0–255)

//+------------------------------------------------------------------+
//| Engine                                                            |
//+------------------------------------------------------------------+
CZigZagLine g_fastZigZag;
CZigZagLine g_slowZigZag;

double   g_fastPeakBuffer[];
double   g_fastBottomBuffer[];
double   g_fastColorBuffer[];

double   g_slowPeakBuffer[];
double   g_slowBottomBuffer[];
double   g_slowColorBuffer[];
int      g_zoneAtrHandle = INVALID_HANDLE;
double   g_lastAtrPips = 0.0;
int      g_lastEffectiveZoneHeightPips = 0;
double   g_lastMaxCapPips = 0.0;
string   g_zoneDebugLabelName = "FXTT_ZZ_ZONE_DEBUG";

//+------------------------------------------------------------------+
int ZZResolveZoneHeightPips()
  {
   int fixedPips = MathMax(1, InpZoneHeight);
   if(!InpUseAtrZoneHeight)
      return fixedPips;

   if(g_zoneAtrHandle == INVALID_HANDLE)
      return fixedPips;

   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
  if(CopyBuffer(g_zoneAtrHandle, 0, 1, 1, atrBuffer) != 1 || atrBuffer[0] <= 0.0)
      return fixedPips;

   double atrPips = atrBuffer[0] / ZZPipSize();
   g_lastAtrPips = atrPips;
   double dynamicPips = atrPips * InpAtrMultiplier;
   dynamicPips = MathMax(dynamicPips, (double)MathMax(1, InpAtrMinZonePips));

  double maxCapPips = (double)MathMax(InpAtrMinZonePips, InpAtrMaxZonePips);
  if(InpUseDynamicAtrMaxCap)
    maxCapPips = atrPips * InpAtrMaxCapMultiplier;
  maxCapPips = MathMax(maxCapPips, (double)MathMax(1, InpAtrMinZonePips));
  g_lastMaxCapPips = maxCapPips;
  dynamicPips = MathMin(dynamicPips, maxCapPips);

   return (int)MathMax(1.0, MathRound(dynamicPips));
  }

//+------------------------------------------------------------------+
void ZZUpdateZoneDebugLabel(const int effectiveZoneHeightPips)
  {
   if(!InpShowZoneDebugLabel)
     {
      ObjectDelete(0, g_zoneDebugLabelName);
      return;
     }

   if(ObjectFind(0, g_zoneDebugLabelName) < 0)
     {
      ObjectCreate(0, g_zoneDebugLabelName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, g_zoneDebugLabelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, g_zoneDebugLabelName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, g_zoneDebugLabelName, OBJPROP_YDISTANCE, 20);
      ObjectSetInteger(0, g_zoneDebugLabelName, OBJPROP_COLOR, clrGainsboro);
      ObjectSetInteger(0, g_zoneDebugLabelName, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, g_zoneDebugLabelName, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, g_zoneDebugLabelName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, g_zoneDebugLabelName, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, g_zoneDebugLabelName, OBJPROP_HIDDEN, true);
     }

   string modeText = InpUseAtrZoneHeight ? "ATR" : "FIXED";
   string atrText = InpUseAtrZoneHeight ? DoubleToString(g_lastAtrPips, 1) : "-";
  string capText = InpUseAtrZoneHeight ? DoubleToString(g_lastMaxCapPips, 1) : "-";
  string text = StringFormat("ZZ Zones | Mode:%s | Effective:%d pips | ATR:%s pips | MaxCap:%s | AutoWiden:%s",
                              modeText,
                              effectiveZoneHeightPips,
                              atrText,
                    capText,
                              InpAutoZoneHeight ? "ON" : "OFF");
   ObjectSetString(0, g_zoneDebugLabelName, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpAtrPeriod < 1)
     {
      Print("ZigZag Zones: ATR period must be >= 1");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpAtrMultiplier <= 0.0)
     {
      Print("ZigZag Zones: ATR multiplier must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpAtrMaxCapMultiplier <= 0.0)
     {
      Print("ZigZag Zones: ATR max cap multiplier must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpUseAtrZoneHeight)
     {
      g_zoneAtrHandle = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
      if(g_zoneAtrHandle == INVALID_HANDLE)
        {
         Print("ZigZag Zones: failed to create ATR handle. Error #", GetLastError());
         return INIT_FAILED;
        }
     }

   ZZBindBuffers(0, g_fastPeakBuffer, g_fastBottomBuffer, g_fastColorBuffer);
   ZZBindBuffers(3, g_slowPeakBuffer, g_slowBottomBuffer, g_slowColorBuffer);

   SZigZagSettings fastSettings;
   fastSettings.depth     = InpFastDepth;
   fastSettings.deviation = InpFastDeviation;
   fastSettings.backstep  = InpFastBackstep;

   SZZLineVisualSettings fastVisual;
   fastVisual.label     = "Fast";
   fastVisual.show      = InpShowFastZZ;
   fastVisual.upColor   = InpFastZZUpColor;
   fastVisual.downColor = InpFastZZDownColor;
   fastVisual.width     = InpFastZZWidth;
   g_fastZigZag.Init(fastSettings, fastVisual);

   SZigZagSettings slowSettings;
   slowSettings.depth     = InpSlowDepth;
   slowSettings.deviation = InpSlowDeviation;
   slowSettings.backstep  = InpSlowBackstep;

   SZZLineVisualSettings slowVisual;
   slowVisual.label     = "Slow";
   slowVisual.show      = InpShowSlowZZ;
   slowVisual.upColor   = InpSlowZZUpColor;
   slowVisual.downColor = InpSlowZZDownColor;
   slowVisual.width     = InpSlowZZWidth;
   g_slowZigZag.Init(slowSettings, slowVisual);

   ZZConfigurePlot(0, g_fastZigZag);
   ZZConfigurePlot(1, g_slowZigZag);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("ZigZag Zones [%s | %s]",
                                   g_fastZigZag.FormatShortName(),
                                   g_slowZigZag.FormatShortName()));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  ObjectDelete(0, g_zoneDebugLabelName);
  if(g_zoneAtrHandle != INVALID_HANDLE)
    {
     IndicatorRelease(g_zoneAtrHandle);
     g_zoneAtrHandle = INVALID_HANDLE;
    }
  ZZDeleteObjects("FXTT_ZZ_R_");
  ZZDeleteObjects("FXTT_ZZ_S_");
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
  {
    int minimumDepth = MathMax(InpFastDepth, InpSlowDepth);
    if(rates_total < minimumDepth + 1)
      return 0;

    ZZUpdateLine(g_fastZigZag,
             rates_total,
             prev_calculated,
             high,
             low,
             time,
             g_fastPeakBuffer,
             g_fastBottomBuffer,
             g_fastColorBuffer);

    ZZUpdateLine(g_slowZigZag,
             rates_total,
             prev_calculated,
             high,
             low,
             time,
             g_slowPeakBuffer,
             g_slowBottomBuffer,
             g_slowColorBuffer);

   int curIdxTime  = ArrayGetAsSeries(time)  ? 0 : (rates_total - 1);
   int curIdxClose = ArrayGetAsSeries(close) ? 0 : (rates_total - 1);
   datetime currentBarTime = time[curIdxTime];
   double   currentPrice   = close[curIdxClose];

   SZZZoneSettings zoneSettings;
  int effectiveZoneHeightPips = ZZResolveZoneHeightPips();
  g_lastEffectiveZoneHeightPips = effectiveZoneHeightPips;
   zoneSettings.show         = InpShowZones;
    zoneSettings.includeFastPivots = InpIncludeFastPivots;
   zoneSettings.lookback     = InpZoneLookback;
  zoneSettings.heightPips   = effectiveZoneHeightPips;
  zoneSettings.autoHeight   = InpAutoZoneHeight;
  zoneSettings.maxHeightMultiplier = InpMaxZoneHeightMult;
   zoneSettings.maxZones     = InpMaxZones;
    zoneSettings.minSlowPivots = InpMinSlowZonePivots;
    zoneSettings.minFastPivots = InpMinFastZonePivots;
   zoneSettings.showBroken   = InpShowBroken;
    zoneSettings.extendRight  = InpExtendZones;
   zoneSettings.resistColor  = InpResistColor;
   zoneSettings.supportColor = InpSupportColor;
   zoneSettings.fill         = InpFillZones;
   zoneSettings.alpha        = InpZoneAlpha;

    ZZRedrawZones(g_slowZigZag,
              g_fastZigZag,
              zoneSettings,
              currentPrice,
              currentBarTime);

    ZZUpdateZoneDebugLabel(g_lastEffectiveZoneHeightPips);

   ChartRedraw(0);

   return rates_total;
  }
