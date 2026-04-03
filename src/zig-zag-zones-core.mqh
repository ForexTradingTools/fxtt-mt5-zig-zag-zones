#ifndef __FXTT_ZIG_ZAG_ZONES_CORE_MQH__
#define __FXTT_ZIG_ZAG_ZONES_CORE_MQH__

#include <FxTT/ZigZag/CZigZag.mqh>

enum ENUM_ZZ_PIVOT_SOURCE
  {
   ZZ_PIVOT_SOURCE_FAST = 0,
   ZZ_PIVOT_SOURCE_SLOW = 1
  };

struct SZZZonePivot
  {
   double               price;
   datetime             time;
   ENUM_ZZ_PIVOT_SOURCE source;
  };

struct SZone
  {
   double    priceSum;
   double    priceHigh;
   double    priceLow;
   int       touches;
   int       slowTouches;
   int       fastTouches;
   datetime  firstTime;
   bool      broken;

   double Center() const { return (touches > 0) ? (priceSum / touches) : 0.0; }
  };

struct SZZLineVisualSettings
  {
   string label;
   bool   show;
   color  upColor;
   color  downColor;
   int    width;

   SZZLineVisualSettings() : label("ZigZag"), show(true), upColor(clrLimeGreen), downColor(clrTomato), width(2) {}
  };

struct SZZZoneSettings
  {
   bool   show;
  bool   includeFastPivots;
   int    lookback;
   int    heightPips;
  bool   autoHeight;
  int    maxHeightMultiplier;
   int    maxZones;
  int    minSlowPivots;
  int    minFastPivots;
   bool   showBroken;
  bool   extendRight;
   color  resistColor;
   color  supportColor;
   bool   fill;
   uchar  alpha;
   string resistPrefix;
   string supportPrefix;

   SZZZoneSettings() : show(true),
                       includeFastPivots(false),
                       lookback(300),
                       heightPips(10),
                       autoHeight(true),
                       maxHeightMultiplier(6),
                       maxZones(5),
                       minSlowPivots(2),
                       minFastPivots(1),
                       showBroken(false),
                       extendRight(true),
                       resistColor(C'210,70,70'),
                       supportColor(C'70,160,90'),
                       fill(true),
                       alpha(45),
                       resistPrefix("FXTT_ZZ_R_"),
                       supportPrefix("FXTT_ZZ_S_") {}
  };

double ZZPipSize()
  {
   return (_Digits == 3 || _Digits == 5) ? _Point * 10.0 : _Point;
  }

void ZZDeleteObjects(const string &prefix)
  {
   ObjectsDeleteAll(0, prefix);
  }

class CZigZagLine
  {
private:
   CZigZag                 m_engine;
   SZigZagSettings         m_settings;
   SZZLineVisualSettings   m_visual;

public:
   void Init(const SZigZagSettings &settings, const SZZLineVisualSettings &visual)
     {
      m_settings = settings;
      m_visual   = visual;
      m_engine.Init(settings);
     }

   void Calculate(const int rates_total,
                  const int prev_calculated,
                  const double &high[],
                  const double &low[],
                  const datetime &time[])
     {
      m_engine.Calculate(rates_total, prev_calculated, high, low, time);
     }

   void FillPlotBuffers(const int rates_total,
                        double &peakBuffer[],
                        double &bottomBuffer[],
                        double &colorBuffer[]) const
     {
      ArrayInitialize(peakBuffer, 0.0);
      ArrayInitialize(bottomBuffer, 0.0);
      ArrayInitialize(colorBuffer, 0.0);

      if(!m_visual.show)
         return;

      int pivotCount = m_engine.GetPivotCount();
      if(pivotCount < 2)
         return;

      for(int pivotIndex = 0; pivotIndex < pivotCount; pivotIndex++)
        {
         SZigZagPivot pivot = m_engine.GetPivot(pivotIndex);
         int bar = pivot.bar;
         if(bar < 0 || bar >= rates_total)
            continue;

         peakBuffer[bar] = 0.0;
         bottomBuffer[bar] = 0.0;

         if(pivot.type == ZZ_PIVOT_HIGH)
            peakBuffer[bar] = pivot.price;
         else
            bottomBuffer[bar] = pivot.price;
        }

      for(int pivotIndex = 1; pivotIndex < pivotCount; pivotIndex++)
        {
         SZigZagPivot previousPivot = m_engine.GetPivot(pivotIndex - 1);
         SZigZagPivot currentPivot  = m_engine.GetPivot(pivotIndex);
         int previousBar = previousPivot.bar;
         int currentBar  = currentPivot.bar;

         if(previousBar < 0 || previousBar >= rates_total || currentBar < 0 || currentBar >= rates_total)
            continue;

         double colorIndex = (currentPivot.price > previousPivot.price) ? 0.0 : 1.0;
         colorBuffer[currentBar] = colorIndex;
         if(pivotIndex == 1)
            colorBuffer[previousBar] = colorIndex;
        }
     }

   int GetPivotCount() const
     {
      return m_engine.GetPivotCount();
     }

   SZigZagPivot GetPivot(const int index) const
     {
      return m_engine.GetPivot(index);
     }

   string GetLabel() const
     {
      return m_visual.label;
     }

   color GetUpColor() const
     {
      return m_visual.upColor;
     }

   color GetDownColor() const
     {
      return m_visual.downColor;
     }

   int GetWidth() const
     {
      return m_visual.width;
     }

   string FormatLabel() const
     {
      return StringFormat("%s (%d,%d,%d)", m_visual.label, m_settings.depth, m_settings.deviation, m_settings.backstep);
     }

   string FormatShortName() const
     {
      return StringFormat("%s=%d,%d,%d", m_visual.label, m_settings.depth, m_settings.deviation, m_settings.backstep);
     }
  };

void ZZBindBuffers(const int baseIndex,
                   double &peakBuffer[],
                   double &bottomBuffer[],
                   double &colorBuffer[])
  {
   SetIndexBuffer(baseIndex, peakBuffer, INDICATOR_DATA);
   SetIndexBuffer(baseIndex + 1, bottomBuffer, INDICATOR_DATA);
   SetIndexBuffer(baseIndex + 2, colorBuffer, INDICATOR_COLOR_INDEX);

   ArraySetAsSeries(peakBuffer, true);
   ArraySetAsSeries(bottomBuffer, true);
   ArraySetAsSeries(colorBuffer, true);
  }

void ZZConfigurePlot(const int plotIndex, const CZigZagLine &line)
  {
   PlotIndexSetDouble(plotIndex, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetInteger(plotIndex, PLOT_COLOR_INDEXES, 2);
   PlotIndexSetInteger(plotIndex, PLOT_LINE_COLOR, 0, line.GetUpColor());
   PlotIndexSetInteger(plotIndex, PLOT_LINE_COLOR, 1, line.GetDownColor());
   PlotIndexSetInteger(plotIndex, PLOT_LINE_WIDTH, line.GetWidth());
   PlotIndexSetString(plotIndex, PLOT_LABEL, line.FormatLabel());
  }

void ZZUpdateLine(CZigZagLine &line,
                  const int rates_total,
                  const int prev_calculated,
                  const double &high[],
                  const double &low[],
                  const datetime &time[],
                  double &peakBuffer[],
                  double &bottomBuffer[],
                  double &colorBuffer[])
  {
   line.Calculate(rates_total, prev_calculated, high, low, time);
   line.FillPlotBuffers(rates_total, peakBuffer, bottomBuffer, colorBuffer);
  }

void ZZDrawZone(const string name,
                const datetime t1,
                const datetime t2,
                const double top,
                const double bottom,
                const color lineColor,
                const bool fill,
                const uchar alpha,
           const bool extendRight,
                const bool broken)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bottom);

   ObjectSetInteger(0, name, OBJPROP_TIME,       0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE,       0, top);
   ObjectSetInteger(0, name, OBJPROP_TIME,       1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE,       1, bottom);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      lineColor);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    ColorToARGB(lineColor, alpha));
   ObjectSetInteger(0, name, OBJPROP_FILL,       fill);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      broken ? STYLE_DOT : STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
  ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  extendRight);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
  }

  void ZZCollectZonePivots(const CZigZagLine &line,
                   const SZZZoneSettings &settings,
                   const bool collectHighs,
                   const ENUM_ZZ_PIVOT_SOURCE source,
                   SZZZonePivot &pivots[],
                   int &pivotCount)
    {
    int linePivotCount = line.GetPivotCount();
    if(linePivotCount <= 0)
      return;

    if(ArraySize(pivots) < pivotCount + linePivotCount)
      ArrayResize(pivots, pivotCount + linePivotCount);

    for(int pivotIndex = 0; pivotIndex < linePivotCount; pivotIndex++)
      {
      SZigZagPivot pivot = line.GetPivot(pivotIndex);
      if(settings.lookback > 0 && pivot.bar > settings.lookback)
        continue;

      bool isHighPivot = (pivot.type == ZZ_PIVOT_HIGH);
      if(isHighPivot != collectHighs)
        continue;

      pivots[pivotCount].price  = pivot.price;
      pivots[pivotCount].time   = pivot.time;
      pivots[pivotCount].source = source;
      pivotCount++;
      }
    }

  void ZZBuildAndDrawZones(const SZZZonePivot &pivots[],
                   const int pivotCount,
                         const bool isResistance,
                         const double zoneHalf,
                         const SZZZoneSettings &settings,
                         const double currentPrice,
                         const datetime currentBarTime,
                         const color zoneColor,
                         const string &prefix)
  {
          if(pivotCount <= 0)
      return;

    SZone zones[];
    int zoneCount = 0;
    double effectiveZoneHalf = MathMax(zoneHalf, ZZPipSize() * 0.5);
    int maxMultiplier = MathMax(1, settings.maxHeightMultiplier);
    if(!settings.autoHeight)
      maxMultiplier = 1;

    for(int multiplier = 1; multiplier <= maxMultiplier; multiplier++)
      {
      effectiveZoneHalf = MathMax(zoneHalf * multiplier, ZZPipSize() * 0.5);
      zoneCount = 0;
      ArrayResize(zones, pivotCount);

      for(int pivotIndex = 0; pivotIndex < pivotCount; pivotIndex++)
        {
        bool merged = false;
        for(int zoneIndex = 0; zoneIndex < zoneCount; zoneIndex++)
          {
          if(MathAbs(pivots[pivotIndex].price - zones[zoneIndex].Center()) <= effectiveZoneHalf * 2.0)
            {
            zones[zoneIndex].priceSum += pivots[pivotIndex].price;
            zones[zoneIndex].priceHigh = MathMax(zones[zoneIndex].priceHigh, pivots[pivotIndex].price);
            zones[zoneIndex].priceLow = MathMin(zones[zoneIndex].priceLow, pivots[pivotIndex].price);
            zones[zoneIndex].touches++;
            if(pivots[pivotIndex].source == ZZ_PIVOT_SOURCE_SLOW)
              zones[zoneIndex].slowTouches++;
            else
              zones[zoneIndex].fastTouches++;
            if(pivots[pivotIndex].time < zones[zoneIndex].firstTime)
              zones[zoneIndex].firstTime = pivots[pivotIndex].time;
            merged = true;
            break;
            }
          }

        if(merged)
          continue;

        zones[zoneCount].priceSum = pivots[pivotIndex].price;
        zones[zoneCount].priceHigh = pivots[pivotIndex].price;
        zones[zoneCount].priceLow = pivots[pivotIndex].price;
        zones[zoneCount].touches = 1;
        zones[zoneCount].slowTouches = (pivots[pivotIndex].source == ZZ_PIVOT_SOURCE_SLOW) ? 1 : 0;
        zones[zoneCount].fastTouches = (pivots[pivotIndex].source == ZZ_PIVOT_SOURCE_FAST) ? 1 : 0;
        zones[zoneCount].firstTime = pivots[pivotIndex].time;
        zones[zoneCount].broken = false;
        zoneCount++;
        }

      for(int zoneIndex = 0; zoneIndex < zoneCount; zoneIndex++)
        {
        zones[zoneIndex].broken = isResistance ? (currentPrice > zones[zoneIndex].priceHigh)
                                  : (currentPrice < zones[zoneIndex].priceLow);
        }

      int drawableCount = 0;
      for(int zoneIndex = 0; zoneIndex < zoneCount; zoneIndex++)
        {
        if(zones[zoneIndex].slowTouches < settings.minSlowPivots)
          continue;
        if(settings.includeFastPivots && zones[zoneIndex].fastTouches < settings.minFastPivots)
          continue;
        if(zones[zoneIndex].broken && !settings.showBroken)
          continue;
        drawableCount++;
        }

      if(drawableCount > 0)
        break;
      }

    for(int leftIndex = 0; leftIndex < zoneCount - 1; leftIndex++)
      {
      for(int rightIndex = leftIndex + 1; rightIndex < zoneCount; rightIndex++)
        {
        if(MathAbs(zones[rightIndex].Center() - currentPrice) >= MathAbs(zones[leftIndex].Center() - currentPrice))
          continue;

        SZone swapZone = zones[leftIndex];
        zones[leftIndex] = zones[rightIndex];
        zones[rightIndex] = swapZone;
        }
      }

   int periodSeconds = PeriodSeconds();
   if(periodSeconds <= 0)
      periodSeconds = 60;

  datetime zoneEndTime = settings.extendRight
                  ? currentBarTime
                  : (datetime)(currentBarTime + (long)periodSeconds * 200);
   int drawnCount = 0;

   for(int zoneIndex = 0; zoneIndex < zoneCount && drawnCount < settings.maxZones; zoneIndex++)
     {
    if(zones[zoneIndex].slowTouches < settings.minSlowPivots)
      continue;
    if(settings.includeFastPivots && zones[zoneIndex].fastTouches < settings.minFastPivots)
         continue;
      if(zones[zoneIndex].broken && !settings.showBroken)
         continue;

      datetime zoneStartTime = zones[zoneIndex].firstTime;
      if(zoneStartTime <= 0 || zoneStartTime > currentBarTime)
         zoneStartTime = currentBarTime;
      if(zoneStartTime >= zoneEndTime)
         zoneStartTime = (datetime)(zoneEndTime - periodSeconds);

      double top = zones[zoneIndex].priceHigh;
      double bottom = zones[zoneIndex].priceLow;
      double minimumHeight = effectiveZoneHalf * 2.0;
      if(top - bottom < minimumHeight)
        {
         double midPrice = zones[zoneIndex].Center();
         top = midPrice + minimumHeight * 0.5;
         bottom = midPrice - minimumHeight * 0.5;
        }

      ZZDrawZone(prefix + IntegerToString(zoneIndex),
                 zoneStartTime,
                 zoneEndTime,
                 top,
                 bottom,
                 zoneColor,
                 settings.fill,
                 settings.alpha,
              settings.extendRight,
                 zones[zoneIndex].broken);
      drawnCount++;
     }
  }

void ZZRedrawZones(const CZigZagLine &line,
                   const SZZZoneSettings &settings,
                   const double currentPrice,
                   const datetime currentBarTime)
  {
   ZZDeleteObjects(settings.resistPrefix);
   ZZDeleteObjects(settings.supportPrefix);
   if(!settings.show)
      return;

  int pivotCount = line.GetPivotCount();
  if(pivotCount < 2)
      return;

   double zoneHalf = settings.heightPips * ZZPipSize() * 0.5;
   SZZZonePivot highPivots[];
   SZZZonePivot lowPivots[];
   int highCount = 0;
   int lowCount = 0;

   ZZCollectZonePivots(line,
                       settings,
                       true,
                       ZZ_PIVOT_SOURCE_SLOW,
                       highPivots,
                       highCount);

   ZZCollectZonePivots(line,
                       settings,
                       false,
                       ZZ_PIVOT_SOURCE_SLOW,
                       lowPivots,
                       lowCount);

   ZZBuildAndDrawZones(highPivots,
                       highCount,
                       true,
                       zoneHalf,
                       settings,
                       currentPrice,
                       currentBarTime,
                       settings.resistColor,
                       settings.resistPrefix);

          ZZBuildAndDrawZones(lowPivots,
                        lowCount,
                       false,
                       zoneHalf,
                       settings,
                       currentPrice,
                       currentBarTime,
                       settings.supportColor,
                       settings.supportPrefix);
  }

        void ZZRedrawZones(const CZigZagLine &slowLine,
                     const CZigZagLine &fastLine,
                     const SZZZoneSettings &settings,
                     const double currentPrice,
                     const datetime currentBarTime)
          {
          ZZDeleteObjects(settings.resistPrefix);
          ZZDeleteObjects(settings.supportPrefix);
          if(!settings.show)
            return;

          int slowPivotCount = slowLine.GetPivotCount();
          if(slowPivotCount < 2)
            return;

          double zoneHalf = settings.heightPips * ZZPipSize() * 0.5;
          SZZZonePivot highPivots[];
          SZZZonePivot lowPivots[];
          int highCount = 0;
          int lowCount = 0;

          ZZCollectZonePivots(slowLine,
                        settings,
                        true,
                        ZZ_PIVOT_SOURCE_SLOW,
                        highPivots,
                        highCount);

          ZZCollectZonePivots(slowLine,
                        settings,
                        false,
                        ZZ_PIVOT_SOURCE_SLOW,
                        lowPivots,
                        lowCount);

          if(settings.includeFastPivots)
            {
            ZZCollectZonePivots(fastLine,
                          settings,
                          true,
                          ZZ_PIVOT_SOURCE_FAST,
                          highPivots,
                          highCount);

            ZZCollectZonePivots(fastLine,
                          settings,
                          false,
                          ZZ_PIVOT_SOURCE_FAST,
                          lowPivots,
                          lowCount);
            }

          ZZBuildAndDrawZones(highPivots,
                        highCount,
                        true,
                        zoneHalf,
                        settings,
                        currentPrice,
                        currentBarTime,
                        settings.resistColor,
                        settings.resistPrefix);

          ZZBuildAndDrawZones(lowPivots,
                        lowCount,
                        false,
                        zoneHalf,
                        settings,
                        currentPrice,
                        currentBarTime,
                        settings.supportColor,
                        settings.supportPrefix);
          }

#endif