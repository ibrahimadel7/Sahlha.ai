import '../../examples/presentation/common/example_shell.dart';

import 'package:flutter/material.dart';

import '../../../../core/theme/sahlha_colors.dart';
import '../../domain/skill_models.dart';
import '../../examples/domain/example_context.dart';
import '../../examples/domain/example_kind.dart';
import '../../examples/domain/example_resolver.dart';
export '../../examples/presentation/adaptive_example_screen.dart'
    show StudentExampleView;
import 'sahlha_avatar.dart';

/// ---------------------------------------------------------------------------
/// Interactive Examples architecture (Student only).
///
/// Retained multiplication renderer and shared legacy exports. Selection lives
/// in the Adaptive Example Engine. No network calls here — callers pass already
/// fetched models. No phone-frame styling.
/// ---------------------------------------------------------------------------

/// Neutral pedagogical defaults used ONLY when the backend provides no
/// parseable numbers. These are generic small facts, not lesson content.
const List<List<int>> kExampleFallbackSeeds = [
  [2, 4],
  [4, 3],
  [5, 5],
];

const int kAreaMin = 1;
const int kAreaMax = 10;
const int kAreaFallbackRows = 3;
const int kAreaFallbackCols = 5;

class MultiplicationSeed {
  const MultiplicationSeed(this.rows, this.cols);
  final int rows;
  final int cols;

  @override
  bool operator ==(Object other) =>
      other is MultiplicationSeed && other.rows == rows && other.cols == cols;
  @override
  int get hashCode => Object.hash(rows, cols);
}

int _clampGrid(int v) => v.clamp(kAreaMin, kAreaMax);

/// Collects every backend text field in priority order (example first).
String _corpus(SkillBundle skill, SkillHelp example) {
  return [
    example.steps.join('\n'),
    example.body,
    example.title,
    skill.explanation,
    skill.description,
    skill.keyConcepts.join('\n'),
    skill.name,
    skill.subject,
  ].join('\n');
}

MultiplicationSeed? _firstPair(String text) {
  // "3 × 5", "3 x 5", "3*5", "3·5" (optionally "= 15").
  final mul = RegExp(r'(\d{1,2})\s*[×xX\*·]\s*(\d{1,2})');
  final m = mul.firstMatch(text);
  if (m != null) {
    final r = int.tryParse(m.group(1)!);
    final c = int.tryParse(m.group(2)!);
    if (r != null && c != null && r >= 1 && c >= 1 && r <= 12 && c <= 12) {
      return MultiplicationSeed(_clampGrid(r), _clampGrid(c));
    }
  }
  // "3 by 5".
  final by = RegExp(r'(\d{1,2})\s+by\s+(\d{1,2})', caseSensitive: false);
  final b = by.firstMatch(text);
  if (b != null) {
    final r = int.tryParse(b.group(1)!);
    final c = int.tryParse(b.group(2)!);
    if (r != null && c != null && r >= 1 && c >= 1 && r <= 12 && c <= 12) {
      return MultiplicationSeed(_clampGrid(r), _clampGrid(c));
    }
  }
  // "3 rows ... 5 columns" (either order).
  final rowsFirst = RegExp(
    r'(\d{1,2})\s*rows?.{0,30}?(\d{1,2})\s*(?:cols?|columns?)',
    caseSensitive: false,
  );
  final rf = rowsFirst.firstMatch(text);
  if (rf != null) {
    final r = int.tryParse(rf.group(1)!);
    final c = int.tryParse(rf.group(2)!);
    if (r != null && c != null && r >= 1 && c >= 1 && r <= 12 && c <= 12) {
      return MultiplicationSeed(_clampGrid(r), _clampGrid(c));
    }
  }
  final colsFirst = RegExp(
    r'(\d{1,2})\s*(?:cols?|columns?).{0,30}?(\d{1,2})\s*rows?',
    caseSensitive: false,
  );
  final cf = colsFirst.firstMatch(text);
  if (cf != null) {
    final c = int.tryParse(cf.group(1)!);
    final r = int.tryParse(cf.group(2)!);
    if (r != null && c != null && r >= 1 && c >= 1 && r <= 12 && c <= 12) {
      return MultiplicationSeed(_clampGrid(r), _clampGrid(c));
    }
  }
  return null;
}

MultiplicationSeed? _repeatedAdditionSeed(String text) {
  // "5 + 5 + 5 = 15" -> rows = term count, cols = term value.
  for (final line in text.split('\n')) {
    if (!line.contains('+')) continue;
    final left = line.split('=').first;
    final nums = RegExp(r'\d{1,2}')
        .allMatches(left)
        .map((m) => int.tryParse(m.group(0)!))
        .whereType<int>()
        .toList();
    if (nums.length >= 2 &&
        nums.length <= 10 &&
        nums.every((n) => n == nums.first) &&
        nums.first >= 1 &&
        nums.first <= 10) {
      return MultiplicationSeed(
        _clampGrid(nums.length),
        _clampGrid(nums.first),
      );
    }
  }
  return null;
}

/// Initial rows/cols from REAL backend data. Falls back to a neutral 3×5
/// only when the backend carries no parseable numbers (never invents
/// lesson content — the grid always stays editable).
MultiplicationSeed parseMultiplicationSeed({
  required SkillBundle skill,
  required SkillHelp example,
}) {
  final corpus = _corpus(skill, example);
  return _firstPair(corpus) ??
      _repeatedAdditionSeed(corpus) ??
      const MultiplicationSeed(kAreaFallbackRows, kAreaFallbackCols);
}

/// Preset facts from REAL backend data first; generic small facts fill
/// remaining slots so "Try these examples" always has three working chips.
List<MultiplicationSeed> parseMultiplicationPresets({
  required SkillBundle skill,
  required SkillHelp example,
  required MultiplicationSeed seed,
}) {
  final corpus = _corpus(skill, example);
  final found = <MultiplicationSeed>[];
  final mul = RegExp(r'(\d{1,2})\s*[×xX\*·]\s*(\d{1,2})');
  for (final m in mul.allMatches(corpus)) {
    final r = int.tryParse(m.group(1)!);
    final c = int.tryParse(m.group(2)!);
    if (r == null || c == null) continue;
    if (r < 1 || c < 1 || r > 12 || c > 12) continue;
    final s = MultiplicationSeed(_clampGrid(r), _clampGrid(c));
    if (s == seed || found.contains(s)) continue;
    found.add(s);
    if (found.length >= 3) break;
  }
  for (final f in kExampleFallbackSeeds) {
    if (found.length >= 3) break;
    final s = MultiplicationSeed(f[0], f[1]);
    if (s == seed || found.contains(s)) continue;
    found.add(s);
  }
  return found.take(3).toList();
}

/// Dispatcher: multiplication/area/array context gets the Area Model;
/// every other subject uses the calm source-backed fallback (reusable).
bool shouldUseAreaModel({
  required SkillBundle skill,
  required SkillHelp example,
}) =>
    const ExampleResolver()
        .resolve(ExampleContext.fromLesson(skill, example))
        .kind ==
    ExampleKind.multiplicationAreaModel;

bool _reduced(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    MediaQuery.accessibleNavigationOf(context);

// ---------------------------------------------------------------------------
// Top-level reusable entry point.
// ---------------------------------------------------------------------------

class AreaModelExample extends StatefulWidget {
  const AreaModelExample({
    super.key,
    required this.skill,
    required this.example,
  });

  final SkillBundle skill;
  final SkillHelp example;

  @override
  State<AreaModelExample> createState() => _AreaModelExampleState();
}

class _AreaModelExampleState extends State<AreaModelExample> {
  late MultiplicationSeed _seed;
  late int _rows;
  late int _cols;
  late List<MultiplicationSeed> _presets;

  @override
  void initState() {
    super.initState();
    _seed = parseMultiplicationSeed(
      skill: widget.skill,
      example: widget.example,
    );
    _rows = _seed.rows;
    _cols = _seed.cols;
    _presets = parseMultiplicationPresets(
      skill: widget.skill,
      example: widget.example,
      seed: _seed,
    );
  }

  @override
  void didUpdateWidget(AreaModelExample oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.example != widget.example ||
        oldWidget.skill != widget.skill) {
      _seed = parseMultiplicationSeed(
        skill: widget.skill,
        example: widget.example,
      );
      _rows = _seed.rows;
      _cols = _seed.cols;
      _presets = parseMultiplicationPresets(
        skill: widget.skill,
        example: widget.example,
        seed: _seed,
      );
    }
  }

  void _setRows(int v) => setState(() => _rows = _clampGrid(v));
  void _setCols(int v) => setState(() => _cols = _clampGrid(v));
  void _apply(MultiplicationSeed s) => setState(() {
    _rows = s.rows;
    _cols = s.cols;
  });
  void _reset() => setState(() {
    _rows = _seed.rows;
    _cols = _seed.cols;
  });

  @override
  Widget build(BuildContext context) {
    final product = _rows * _cols;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExamplesHeroBanner(),
        const SizedBox(height: 14),
        AreaModelCard(
          rows: _rows,
          cols: _cols,
          product: product,
          presets: _presets,
          onRowsChanged: _setRows,
          onColsChanged: _setCols,
          onPreset: _apply,
          onReset: _reset,
        ),
        const SizedBox(height: 14),
        ExpansionTile(
          title: const Text('See repeated addition'),
          children: [
            RepeatedAdditionCard(rows: _rows, cols: _cols, product: product),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero banner (matches reference: light-blue card, intro, avatar, speech).
// ---------------------------------------------------------------------------

class ExamplesHeroBanner extends StatelessWidget {
  const ExamplesHeroBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SahlhaColors.skySoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SahlhaColors.borderSubtle),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 380;
          final intro = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SahlhaColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Let\u2019s build an array together!',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E3A5F),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'You can change the numbers and see how the area model shows multiplication.',
                  style: text.bodyMedium?.copyWith(
                    color: SahlhaColors.muted,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          );
          final avatar = const SahlhaAvatar(
            size: 84,
            state: SahlhaAvatarState.encouraging,
          );
          const speech = _SpeechNote(message: 'Each square represents 1 unit!');
          if (narrow) {
            return Column(
              children: [
                intro,
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    avatar,
                    const SizedBox(width: 10),
                    const Flexible(child: speech),
                  ],
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: intro),
              const SizedBox(width: 8),
              avatar,
              const SizedBox(width: 8),
              const Expanded(
                flex: 3,
                child: _SpeechNote(message: 'Each square represents 1 unit!'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SpeechNote extends StatelessWidget {
  const _SpeechNote({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SahlhaColors.borderSubtle),
        boxShadow: SahlhaShadows.soft,
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: text.bodySmall?.copyWith(
          color: const Color(0xFF1E3A5F),
          fontWeight: FontWeight.w700,
          height: 1.45,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main area-model card: steppers, live grid, fact, presets, reset.
// ---------------------------------------------------------------------------

class AreaModelCard extends StatelessWidget {
  const AreaModelCard({
    super.key,
    required this.rows,
    required this.cols,
    required this.product,
    required this.presets,
    required this.onRowsChanged,
    required this.onColsChanged,
    required this.onPreset,
    required this.onReset,
  });

  final int rows;
  final int cols;
  final int product;
  final List<MultiplicationSeed> presets;
  final ValueChanged<int> onRowsChanged;
  final ValueChanged<int> onColsChanged;
  final ValueChanged<MultiplicationSeed> onPreset;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SahlhaColors.borderSubtle),
        boxShadow: SahlhaShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepperRow(
            rows: rows,
            cols: cols,
            onRowsChanged: onRowsChanged,
            onColsChanged: onColsChanged,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 340;
              final grid = AreaModelGrid(rows: rows, cols: cols);
              final fact = MultiplicationFactPanel(
                rows: rows,
                cols: cols,
                product: product,
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [grid, const SizedBox(height: 12), fact],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: grid),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: fact),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _PresetStrip(
            presets: presets,
            rows: rows,
            cols: cols,
            onPreset: onPreset,
            onReset: onReset,
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.rows,
    required this.cols,
    required this.onRowsChanged,
    required this.onColsChanged,
  });
  final int rows, cols;
  final ValueChanged<int> onRowsChanged, onColsChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceAround,
    spacing: 16,
    runSpacing: 12,
    children: [
      ExampleCounter(
        label: 'rows',
        value: rows,
        min: kAreaMin,
        max: kAreaMax,
        onChanged: onRowsChanged,
      ),
      ExampleCounter(
        label: 'columns',
        value: cols,
        min: kAreaMin,
        max: kAreaMax,
        onChanged: onColsChanged,
      ),
    ],
  );
}

class AreaModelGrid extends StatelessWidget {
  const AreaModelGrid({super.key, required this.rows, required this.cols});
  final int rows, cols;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '$rows rows by $cols columns, ${rows * cols} squares',
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text('$rows rows'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final cell = (constraints.maxWidth / cols).clamp(0.0, 32.0);
              return Center(
                child: SizedBox(
                  width: cell * cols,
                  height: cell * rows,
                  child: ExcludeSemantics(
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                      ),
                      itemCount: rows * cols,
                      itemBuilder: (context, i) => AnimatedContainer(
                        key: ValueKey('area-cell-$i'),
                        duration: _reduced(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: SahlhaColors.joyTeal,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text('$cols columns'),
        ],
      ),
    ),
  );
}

class MultiplicationFactPanel extends StatelessWidget {
  const MultiplicationFactPanel({
    super.key,
    required this.rows,
    required this.cols,
    required this.product,
  });
  final int rows;
  final int cols;
  final int product;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: SahlhaColors.surfaceTealSoft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: SahlhaColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Multiplication fact',
                style: text.bodySmall?.copyWith(
                  color: const Color(0xFF1E3A5F),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Semantics(
                liveRegion: true,
                label: '$rows times $cols equals $product',
                child: Text(
                  '$rows \u00d7 $cols = $product',
                  style: text.headlineSmall?.copyWith(
                    color: SahlhaColors.joyTealDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$rows rows of $cols = $product squares',
                style: text.bodySmall?.copyWith(
                  color: const Color(0xFF1E3A5F),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SahlhaColors.successSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: SahlhaColors.success.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: SahlhaColors.success,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The area model shows multiplication as an array!',
                  style: text.bodySmall?.copyWith(
                    color: const Color(0xFF14532D),
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Presets + reset.
// ---------------------------------------------------------------------------

class _PresetStrip extends StatelessWidget {
  const _PresetStrip({
    required this.presets,
    required this.rows,
    required this.cols,
    required this.onPreset,
    required this.onReset,
  });
  final List<MultiplicationSeed> presets;
  final int rows;
  final int cols;
  final ValueChanged<MultiplicationSeed> onPreset;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SahlhaColors.skySoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SahlhaColors.borderSubtle),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 420;
          final chips = [
            for (var i = 0; i < presets.length; i++)
              _PresetChip(
                seed: presets[i],
                selected: presets[i].rows == rows && presets[i].cols == cols,
                color: [
                  SahlhaColors.sky,
                  SahlhaColors.lavender,
                  const Color(0xFF4CC38A),
                ][i % 3],
                onTap: () => onPreset(presets[i]),
              ),
          ];
          final reset = Semantics(
            button: true,
            label: 'Reset grid',
            child: OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Reset'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Try these examples:',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E3A5F),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: chips),
                const SizedBox(height: 8),
                reset,
              ],
            );
          }
          return Row(
            children: [
              Text(
                'Try these\nexamples:',
                style: text.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E3A5F),
                  height: 1.3,
                ),
              ),
              const SizedBox(width: 10),
              ...[
                for (final c in chips) ...[
                  Expanded(child: c),
                  const SizedBox(width: 8),
                ],
              ],
              Container(width: 1, height: 44, color: SahlhaColors.borderSubtle),
              const SizedBox(width: 8),
              reset,
            ],
          );
        },
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.seed,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final MultiplicationSeed seed;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Try ${seed.rows} by ${seed.cols}',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? SahlhaColors.joyTeal : SahlhaColors.borderSubtle,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${seed.rows} \u00d7 ${seed.cols}',
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E3A5F),
                  ),
                ),
                const SizedBox(width: 8),
                MiniArrayPreview(
                  rows: seed.rows,
                  cols: seed.cols,
                  color: color,
                  cell: 9,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny non-interactive array preview used inside preset chips/cards.
class MiniArrayPreview extends StatelessWidget {
  const MiniArrayPreview({
    super.key,
    required this.rows,
    required this.cols,
    required this.color,
    this.cell = 9,
  });
  final int rows;
  final int cols;
  final Color color;
  final double cell;

  @override
  Widget build(BuildContext context) {
    final r = rows.clamp(1, 6);
    final c = cols.clamp(1, 6);
    return ExcludeSemantics(
      child: SizedBox(
        width: c * (cell + 3),
        child: Wrap(
          spacing: 3,
          runSpacing: 3,
          children: [
            for (var i = 0; i < r * c; i++)
              Container(
                width: cell,
                height: cell,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "See it another way" — repeated addition, always synced.
// ---------------------------------------------------------------------------

class RepeatedAdditionCard extends StatelessWidget {
  const RepeatedAdditionCard({
    super.key,
    required this.rows,
    required this.cols,
    required this.product,
  });
  final int rows;
  final int cols;
  final int product;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final equationLabel =
        "${List.filled(rows, '$cols').join(' plus ')} equals $product";
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SahlhaColors.warmYellowSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: SahlhaColors.warmYellow.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: SahlhaColors.warmYellow.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lightbulb_rounded,
                  color: Color(0xFFB45309),
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(child: _RepeatedHeaderText()),
              const Column(
                children: [
                  SahlhaAvatar(size: 56, state: SahlhaAvatarState.encouraging),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: equationLabel,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < rows; i++) ...[
                          _TermChip(value: '$cols'),
                          if (i != rows - 1)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                '+',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E3A5F),
                                ),
                              ),
                            ),
                        ],
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '=',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E3A5F),
                            ),
                          ),
                        ),
                        _TermChip(value: '$product', result: true),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _AvatarNote(
                message:
                    'You\u2019re adding $cols $rows time${rows == 1 ? '' : 's'} \u2014 one for each row!',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'The same multiplication can be shown as repeated addition.',
            style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
          ),
        ],
      ),
    );
  }
}

class _RepeatedHeaderText extends StatelessWidget {
  const _RepeatedHeaderText();
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'See it another way',
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1E3A5F),
          ),
        ),
        Text(
          'The same multiplication can be shown as repeated addition.',
          style: text.bodySmall?.copyWith(
            color: SahlhaColors.muted,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _TermChip extends StatelessWidget {
  const _TermChip({required this.value, this.result = false});
  final String value;
  final bool result;
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 56, minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: result ? Colors.white : const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: result
              ? SahlhaColors.joyTeal.withValues(alpha: 0.5)
              : const Color(0xFFD0E0FF),
          width: result ? 2 : 1.2,
        ),
      ),
      child: Text(
        value,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF1E3A5F),
        ),
      ),
    );
  }
}

class _AvatarNote extends StatelessWidget {
  const _AvatarNote({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SahlhaColors.borderSubtle),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF4C1D95),
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Try different numbers" — large preset cards.
// ---------------------------------------------------------------------------

class TryDifferentNumbersCard extends StatelessWidget {
  const TryDifferentNumbersCard({
    super.key,
    required this.rows,
    required this.cols,
    required this.presets,
    required this.onPreset,
  });
  final int rows;
  final int cols;
  final List<MultiplicationSeed> presets;
  final ValueChanged<MultiplicationSeed> onPreset;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = [
      SahlhaColors.sky,
      SahlhaColors.lavender,
      const Color(0xFF4CC38A),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SahlhaColors.lavenderSoft.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: SahlhaColors.lavender.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: SahlhaColors.lavender.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sports_esports_rounded,
                  color: SahlhaColors.lavenderDark,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Try different numbers',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E3A5F),
                      ),
                    ),
                    Text(
                      'Change the numbers and see what happens!',
                      style: text.bodySmall?.copyWith(
                        color: SahlhaColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 420;
              Widget card(int i) => _BigPresetCard(
                seed: presets[i],
                selected: presets[i].rows == rows && presets[i].cols == cols,
                color: colors[i % colors.length],
                onTap: () => onPreset(presets[i]),
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < presets.length; i++) ...[
                      card(i),
                      if (i != presets.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < presets.length; i++) ...[
                    Expanded(child: card(i)),
                    if (i != presets.length - 1) const SizedBox(width: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BigPresetCard extends StatelessWidget {
  const _BigPresetCard({
    required this.seed,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final MultiplicationSeed seed;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label:
          'Try ${seed.rows} by ${seed.cols}, ${seed.rows * seed.cols} squares',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? SahlhaColors.joyTeal : SahlhaColors.borderSubtle,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${seed.rows} \u00d7 ${seed.cols}',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E3A5F),
                  ),
                ),
                const SizedBox(width: 12),
                MiniArrayPreview(
                  rows: seed.rows,
                  cols: seed.cols,
                  color: color,
                  cell: 11,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generic fallback for non-multiplication subjects (reusable architecture).
// Uses ONLY real backend text — never invented visuals.
// ---------------------------------------------------------------------------
