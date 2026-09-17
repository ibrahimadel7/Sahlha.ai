import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Source-backed idea diagram. Selecting a label reveals its full explanation;
/// connections express association, not an invented scientific relationship.
class ConceptDiagram extends StatelessWidget {
  const ConceptDiagram({
    super.key,
    required this.title,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });
  final String title;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Icon(Icons.science_outlined, size: 36, color: Color(0xFF4F8542)),
      Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 10),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < labels.length; i++)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: ChoiceChip(
                selected: selected == i,
                label: Text(
                  labels[i],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onSelected: (_) => onSelect(i),
              ),
            ),
        ],
      ),
    ],
  );
}

class LessonTimeline extends StatelessWidget {
  const LessonTimeline({
    super.key,
    required this.events,
    required this.selected,
    required this.onSelect,
  });
  final List<String> events;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < events.length; i++)
        if ((i - selected).abs() <= 1)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          width: 2,
                          color: const Color(0xFFD8BD94),
                        ),
                      ),
                      Icon(
                        selected == i
                            ? Icons.radio_button_checked
                            : Icons.circle_outlined,
                        size: 18,
                        color: const Color(0xFF976E3E),
                      ),
                      Expanded(
                        child: Container(
                          width: 2,
                          color: const Color(0xFFD8BD94),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Card(
                    color: selected == i
                        ? Colors.white
                        : const Color(0xFFFAEACC),
                    child: InkWell(
                      onTap: () => onSelect(i),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          events[i],
                          maxLines: selected == i ? null : 2,
                          overflow: selected == i
                              ? null
                              : TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    ],
  );
}

/// Coordinates are read from the lesson, never geocoded or invented.
class CoordinatePlot extends StatefulWidget {
  const CoordinatePlot({
    super.key,
    required this.source,
    this.geographic = false,
  });
  final String source;
  final bool geographic;
  @override
  State<CoordinatePlot> createState() => _CoordinatePlotState();
}

class _CoordinatePlotState extends State<CoordinatePlot> {
  int _selected = 0;
  @override
  Widget build(BuildContext context) {
    final points = <Offset>[];
    final labels = <String>[];
    final expression = widget.geographic
        ? RegExp(
            r'(\d+(?:\.\d+)?)\s*°?\s*([NS])\s*[,; ]+\s*(\d+(?:\.\d+)?)\s*°?\s*([EW])',
            caseSensitive: false,
          )
        : RegExp(r'\((-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\)');
    for (final match in expression.allMatches(widget.source).take(20)) {
      if (widget.geographic) {
        final lat =
            double.parse(match.group(1)!) *
            (match.group(2)!.toUpperCase() == 'S' ? -1 : 1);
        final lon =
            double.parse(match.group(3)!) *
            (match.group(4)!.toUpperCase() == 'W' ? -1 : 1);
        if (lat.abs() > 90 || lon.abs() > 180) continue;
        points.add(Offset(lon, lat));
      } else {
        final point = Offset(
          double.parse(match.group(1)!),
          double.parse(match.group(2)!),
        );
        if (!point.dx.isFinite || !point.dy.isFinite) continue;
        points.add(point);
      }
      labels.add(match.group(0)!);
    }
    if (points.isEmpty) return const SizedBox.shrink();
    final index = _selected.clamp(0, points.length - 1);
    return Column(
      children: [
        Text(
          widget.geographic
              ? 'Latitude / longitude'
              : 'Coordinates from your lesson',
        ),
        const SizedBox(height: 8),
        Semantics(
          image: true,
          label:
              '${widget.geographic ? "Location" : "Point"}: ${labels[index]}',
          child: SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              painter: _PlotPainter(points, index, widget.geographic),
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          children: [
            for (var i = 0; i < labels.length; i++)
              ChoiceChip(
                label: Text(labels[i]),
                selected: i == index,
                onSelected: (_) => setState(() => _selected = i),
              ),
          ],
        ),
      ],
    );
  }
}

class _PlotPainter extends CustomPainter {
  const _PlotPainter(this.points, this.selected, this.geographic);
  final List<Offset> points;
  final int selected;
  final bool geographic;
  @override
  void paint(Canvas canvas, Size size) {
    final extentX = geographic
        ? 180.0
        : math.max(1.0, points.map((p) => p.dx.abs()).reduce(math.max)) * 1.25;
    final extentY = geographic
        ? 90.0
        : math.max(1.0, points.map((p) => p.dy.abs()).reduce(math.max)) * 1.25;
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()..color = const Color(0xFFE4F3F0),
    );
    final grid = Paint()
      ..color = const Color(0xFFB3D7D0)
      ..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      final x = rect.left + rect.width * i / 6;
      final y = rect.top + rect.height * i / 6;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
    final axis = Paint()
      ..color = const Color(0xFF54877F)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(rect.center.dx, rect.top),
      Offset(rect.center.dx, rect.bottom),
      axis,
    );
    canvas.drawLine(
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      axis,
    );
    for (var i = 0; i < points.length; i++) {
      final position = Offset(
        rect.center.dx + points[i].dx / extentX * rect.width / 2,
        rect.center.dy - points[i].dy / extentY * rect.height / 2,
      );
      canvas.drawCircle(
        position,
        i == selected ? 8 : 5,
        Paint()
          ..color = i == selected
              ? const Color(0xFFC17821)
              : const Color(0xFF087D77),
      );
    }
  }

  @override
  bool shouldRepaint(_PlotPainter old) =>
      old.selected != selected ||
      old.points != points ||
      old.geographic != geographic;
}
