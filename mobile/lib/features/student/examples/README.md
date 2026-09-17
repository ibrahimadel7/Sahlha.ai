# Adaptive Example Engine

The student lesson screen retains its Learn / Examples / Practice navigation, cached example request, authenticated read-aloud control, and practice routing. Examples now resolve to a curated native Flutter experience. Presentation interactions do not access the repository or change mastery.

## Architecture discovered and retained

Previously, `presentation/widgets/interactive_examples.dart` selected the area model for almost any mathematical term and displayed other topics as passive text. Its existing multiplication components and source seed/preset helpers are retained. `learning_playground.dart` and `playgrounds_joy.dart` belong to Learn and retain their existing behavior. The existing bounded `LoopTrace` parser moved into this engine's domain; its old import path re-exports it.

## Flow

`AdaptiveExampleScreen` -> `ExampleContext` -> generated `exampleSelectionProvider` -> `ExampleResolver` -> `ExampleMatch` -> `ExampleRendererRegistry` -> native renderer (or `ConceptExplorerExample`).

Normalization happens when lesson inputs change. The Riverpod codegen provider selects an experience; local widget state owns controls, selection, steps and timers. A new context keys a fresh renderer subtree, so values cannot leak between lessons. Server state stays outside the engine.

## Context and metadata

`ExampleContext` contains subject, courseName, lessonTitle, skillId, skillName, description, learningObjective, keyConcepts, explanation, examples, steps, difficulty, visualType, visualSpec, playgroundSpec, sourceType and rawMetadata. Strings and optional collections are normalized safely. Invalid item entries are discarded. The original skill/help are retained for compatibility with multiplication seed helpers.

`SkillBundle` and `SkillHelp` preserve response metadata for this adapter. It recognizes top-level fields and nested `learning_content`, including `core_idea`, `example`, `steps`, `visual_type`, `visual_spec.items` (label/detail), `visual_spec.source_text`, and `playground`.

The current `platform.skill_bundle` and example-help response mostly return legacy name/description/explanation/key-concept fields; they do not currently return the full internal `LearningContent` object. The frontend consumes structured metadata whenever supplied, and does not require an endpoint change. Legacy science sentences and dated history sentences can supply source-backed sequences without inventing facts. Source order is preserved; the UI does not infer scientific causality or sort historical eras.

## Selection

Supported, validated visual types have priority. Backend aliases include `loop_flow`, `process_sequence`, `number_line`, `equation_steps`, `code_trace`, `variable_state`, `condition_flow`, `labeled_diagram`, `timeline`, and `sentence_builder`. `number_line` requires addition/subtraction evidence. Unsupported metadata is ignored and semantic resolution continues.

Semantic scores: topic/objective/key-concept match +65, description/lesson match +25, matching subject/course +20. The threshold is 65. Competing matches within 15 points fall back, with a specific circle-fraction match preferred over broad fraction bars. Known conflicting subjects and unsupported advanced concepts are rejected. Confidence is a normalized heuristic score, not a calibrated probability.

Content validation rejects unsupported arithmetic values, improper/zero-denominator fractions, unknown equation forms and unsupported source code. Processes/timelines need at least two source entries; schematic diagrams need labeled items; sentences need a bounded supplied sentence. The registry validates again before constructing a renderer.

Debug builds can enable a collapsed selection diagnostic with `--dart-define=EXAMPLE_DEBUG=true`. It shows the selected kind, score and matched signals; release builds omit it.

## Implemented kinds and coverage

| ExampleKind | Interaction |
| --- | --- |
| multiplicationAreaModel | Source-seeded rows/columns, bounded animated grid, equation, presets/reset, revealable repeated addition |
| multiplicationGroups | Larger whole-number source products (factors 0–1000), editable equal groups, running totals, reveal all and reset |
| additionNumberLine | Forward single-step jumps, editable start/jump count, synchronized position/result |
| subtractionNumberLine | Backward jumps including landing below zero |
| fractionBars | Equal parts, bounded numerator/denominator, simplified equivalent amount |
| fractionCircle | Explicit circle/pie representation of equal parts |
| equationSteps | Source-backed `ax + b = c`, reveal subtraction/division and reasons |
| codeTrace | Supplied trace items or bounded assignment/addition/print demonstration |
| loopTrace | Existing bounded counter-loop parser, line/state/output, next/run/pause/reset |
| conditionFlow | Clearly labeled illustrative numeric condition with selectable true/false branch |
| variableState | Assignment state changes through the shared safe trace renderer |
| processFlow | Lesson-provided stages/sentences, arrows, selection and detail reveal |
| labeledDiagram | Labeled schematic components, tap/reveal; no invented anatomical positions |
| timeline | Supplied event labels and dates on a vertical timeline, selected detail |
| sentenceBuilder | Source word tokens, guided ordering, undo, hint, reveal/reset; no scoring |
| conceptExplorer | Short idea pages, source explanation/example disclosure, concept connections, prediction/reflection |

Native defaults are illustrative elementary demonstrations, not fabricated lesson facts. Addition/subtraction inputs are 0-12 (results may be negative); multiplication controls are 1-10; fractions are proper fractions with up to 12 parts. Unsupported supplied values resolve to the explorer rather than silently changing the arithmetic. Algebra currently requires an integer solution of a single positive-coefficient `ax + b = c` form. Assignment traces recognize only the bounded assignment/addition/optional-print template. Loop code recognizes the existing bounded incrementing while-loop template. Arbitrary code is never evaluated.

## Interaction, accessibility and audio

Skill-title matches outrank related concepts in descriptions. Repeated addition resolves to multiplication unless the title also explicitly requests a separate addition activity. Multiplication outside the 1–10 unit-grid range uses the equal-groups activity when its source factors are whole numbers within 0–1000. Lesson steps and visual source text participate in both validation and initialization. Generic exploration presents supplied examples first, with progress and previous/next navigation.

The shared shell uses the current Sahlha avatar, rounded white cards and teal actions within the existing cream lesson canvas. Number-line position, fraction shading, grid cells, code selection and equation reveals use calm 200-280ms transitions. Step controls, source chips and buttons support tap/keyboard interaction without dragging. State/result semantics announce meaningful values, and visual-only grid/paint details are excluded from duplicate announcements.

Layout uses wrapping controls and constrained visual regions; widget tests cover every kind at 320px and 200% text scale. Both disabled animations and accessible navigation remove animation/automatic walkthrough controls. Active walkthrough timers stop when reduced motion becomes enabled and are disposed on navigation. Source code and long labels wrap.

Examples receive the existing authenticated `ReadAloudButton`. Selection and control changes issue no audio request. Playback state/companion animation continue to belong to the existing audio architecture; no endpoint, token handling or audio service was added.

## Fallback and future coverage

Unknown/ambiguous topics, geography, classification, general comparisons, coordinate graphs, geometry, advanced algebra, unsupported programs, improper fractions and lessons lacking sufficient grounded sequence/sentence data use the concept explorer. Non-English semantic topic recognition is currently conservative (subject checks include Arabic math terms); explicit supported metadata can still select native experiences.

Useful next additions: source-backed coordinate graphs with existing fl_chart, equation balance, classification, geography relationships, comparison cards, vocabulary context, and wider multilingual resolver fixtures. Add a domain capability, validation, registry builder and tests together rather than advertising unfinished kinds.

## Changes and verification

New files are under `examples/domain/`, `examples/application/`, `examples/presentation/common/` and `examples/presentation/renderers/`. Integration changes are in `domain/skill_models.dart`, `presentation/skill_lesson_screen.dart`, `presentation/widgets/interactive_examples.dart`, and the compatibility export `presentation/widgets/loop_trace.dart`.

Tests: `test/example_resolver_test.dart`, `test/adaptive_examples_test.dart`, and extended `test/area_model_test.dart`. They cover semantic and explicit resolution, ambiguity/domain rejection, malformed/minimal metadata, legacy source sequences, numeric/code rejection, registry completeness, state synchronization, lesson changes, source traces, equation operations, sentence ordering, timeline disclosure, reduced motion and narrow layouts. Existing audio, navigation, mastery and other student tests remain in the full suite.

No packages were added. `flutter pub get`, code generation, formatting, analysis and the full test suite were run. Generated Dart remains ignored according to the repository convention and can be regenerated with build_runner. The installed build_runner accepts the requested command but reports that `--delete-conflicting-outputs` is obsolete and ignored. Final verification: `flutter test` passed all 130 tests. `flutter analyze` reported no errors or warnings and two pre-existing informational `use_null_aware_elements` notices in `features/materials/data/material_repository.dart:156-157` (therefore its exit code was 1). `git diff --check` passed. No physical Android device or manual screen-reader session was used.
