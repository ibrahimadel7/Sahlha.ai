import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/example_context.dart';
import '../domain/example_match.dart';
import '../domain/example_resolver.dart';
part 'example_selection_provider.g.dart';

@riverpod
ExampleMatch exampleSelection(Ref ref, ExampleContext context) =>
    const ExampleResolver().resolve(context);
