import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../data/dates.dart';
import '../../../engine/engine.dart';
import '../../theme.dart';
import 'progress_data.dart';

/// The trend line chart of the Progress tab (specs/ui.md §7.1) on `fl_chart`: dashed gridlines
/// on "nice" steps, month ticks, an accent area under a 2.5 px line, optional marker dots, a
/// dashed yellow [goal] line, the last point as a solid dot, and a touch tooltip
/// "`{date} · {value} {unit} · {note}`" for the nearest point.
///
/// [invert] flips the y axis for a scale that counts down as it gets harder (RIR), so harder
/// sets still plot higher. Axis labels are laid out here, around the plot, with the original's
/// paddings; `fl_chart` draws the plot itself.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.points,
    this.height = 150,
    this.unit = '',
    this.color,
    this.goal,
    this.invert = false,
  });

  /// Sorted by `t`.
  final List<ChartPoint> points;
  final double height;
  final String unit;

  /// Defaults to the accent.
  final Color? color;
  final num? goal;
  final bool invert;

  static const _pad = EdgeInsets.fromLTRB(34, 10, 12, 22);
  static const _labelSize = 9.5;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const ChartEmpty();
    final frame = ChartFrame.of(points, goal: goal);
    final p = context.palette;
    final labelStyle = TextStyle(fontSize: _labelSize, color: p.label2, height: 1);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          final plot = Rect.fromLTRB(_pad.left, _pad.top, box.maxWidth - _pad.right, height - _pad.bottom);
          double yPx(num v) => plot.top + (invert ? frame.yFraction(v) : 1 - frame.yFraction(v)) * plot.height;
          double xPx(int t) => plot.left + frame.xFraction(t) * plot.width;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final v in frame.gridValues)
                Positioned(
                  left: 0,
                  width: plot.left - 5,
                  top: yPx(v) - _labelSize / 2,
                  child: Text(fmtNum(v), textAlign: TextAlign.right, style: labelStyle),
                ),
              for (final tick in frame.ticks) _tickLabel(tick, xPx(tick.t), box.maxWidth, labelStyle),
              if (goal case final g? when g.isFinite)
                Positioned(
                  right: _pad.right + 2,
                  top: yPx(g) - 5 - _labelSize,
                  child: Text(
                    fmtNum(g),
                    style: labelStyle.copyWith(color: p.yellow, fontWeight: FontWeight.w700),
                  ),
                ),
              Positioned.fromRect(
                rect: plot,
                child: LineChart(
                  _chartData(context, frame),
                  duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.med,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tickLabel(ChartTick tick, double x, double width, TextStyle style) {
    const box = 64.0;
    final text = Text(tick.label, style: style, maxLines: 1, softWrap: false);
    final top = height - 7 - _labelSize;
    return switch (tick.anchor) {
      TickAnchor.start => Positioned(left: x, top: top, child: text),
      TickAnchor.end => Positioned(right: width - x, top: top, child: text),
      TickAnchor.middle => Positioned(
        left: x - box / 2,
        width: box,
        top: top,
        child: Text(tick.label, style: style, maxLines: 1, softWrap: false, textAlign: TextAlign.center),
      ),
    };
  }

  /// `fl_chart` has no inverted axis, so an inverted chart plots `-y` and the frame mirrors.
  double _plotY(num y) => invert ? -y.toDouble() : y.toDouble();

  LineChartData _chartData(BuildContext context, ChartFrame frame) {
    final p = context.palette;
    final color = this.color ?? p.acc;
    final x0 = frame.t0;
    double x(int t) => (t - x0) / dayMs;
    final span = x(frame.t1);
    final single = span == 0;
    final minY = invert ? -frame.yMax : frame.yMin;
    final maxY = invert ? -frame.yMin : frame.yMax;
    final grid = FlLine(color: p.sepOp, strokeWidth: 1, dashArray: const [2, 4]);
    final lastIndex = points.length - 1;
    return LineChartData(
      minX: single ? -1 : 0,
      maxX: single ? 1 : span,
      minY: minY,
      maxY: maxY,
      titlesData: const FlTitlesData(show: false),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      extraLinesData: ExtraLinesData(
        extraLinesOnTop: false,
        horizontalLines: [
          for (final v in frame.gridValues)
            HorizontalLine(y: _plotY(v), color: grid.color, strokeWidth: 1, dashArray: grid.dashArray),
          if (goal case final g? when g.isFinite)
            HorizontalLine(y: _plotY(g), color: p.yellow, strokeWidth: 1.6, dashArray: const [7, 4]),
        ],
        verticalLines: [
          for (final tick in frame.ticks)
            VerticalLine(x: x(tick.t), color: grid.color, strokeWidth: 1, dashArray: grid.dashArray),
        ],
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [for (final pt in points) FlSpot(single ? 0 : x(pt.t), _plotY(pt.y))],
          color: color,
          barWidth: 2.5,
          isStrokeCapRound: true,
          isStrokeJoinRound: true,
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: .28), color.withValues(alpha: 0)],
            ),
          ),
          dotData: FlDotData(
            getDotPainter: (spot, _, _, index) {
              if (index == lastIndex) return FlDotCirclePainter(radius: 4, color: color, strokeWidth: 0);
              final m = points[index].m;
              if (m == null) return FlDotCirclePainter(radius: 0, color: Colors.transparent, strokeWidth: 0);
              return FlDotCirclePainter(
                radius: 2.4 + 3 * m,
                color: color.withValues(alpha: .3 + .7 * m),
                strokeWidth: 0,
              );
            },
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchSpotThreshold: double.infinity,
        getTouchLineStart: (_, _) => maxY,
        getTouchLineEnd: (_, _) => minY,
        getTouchedSpotIndicator: (_, indexes) => [
          for (final _ in indexes)
            TouchedSpotIndicatorData(
              FlLine(color: p.label3, strokeWidth: 1, dashArray: const [3, 3]),
              FlDotData(
                getDotPainter: (_, _, _, _) =>
                    FlDotCirclePainter(radius: 5, color: color, strokeColor: p.bg, strokeWidth: 2),
              ),
            ),
        ],
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => p.surface2,
          tooltipBorderRadius: BorderRadius.circular(8),
          tooltipPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          tooltipMargin: 10,
          maxContentWidth: 240,
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                _tooltip(points[s.spotIndex]),
                TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.label),
              ),
          ],
        ),
      ),
    );
  }

  String _tooltip(ChartPoint point) {
    final iso = point.d ?? isoDate(DateTime.fromMillisecondsSinceEpoch(point.t));
    return [fmtDate(iso, long: true), fmtNum(point.y) + (unit.isEmpty ? '' : ' $unit'), ?point.note].join(' · ');
  }
}

/// "Aún sin datos" in place of an empty chart.
class ChartEmpty extends StatelessWidget {
  const ChartEmpty({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Text('Aún sin datos', textAlign: TextAlign.center, style: context.textStyles.small),
  );
}
