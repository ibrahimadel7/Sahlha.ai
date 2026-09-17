import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../classrooms/data/classroom_repository.dart';

class JoinClassroomScreen extends ConsumerStatefulWidget {
  const JoinClassroomScreen({super.key});

  @override
  ConsumerState<JoinClassroomScreen> createState() =>
      _JoinClassroomScreenState();
}

class _JoinClassroomScreenState extends ConsumerState<JoinClassroomScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(classroomRepositoryProvider).join(code);
      ref.invalidate(classroomListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.alreadyEnrolled
                  ? 'You are already in ${result.classroom.name}.'
                  : 'Welcome to ${result.classroom.name}!',
            ),
          ),
        );
        context.go('/student/home');
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const SahlhaAppBar(title: 'Join a classroom'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter your classroom code', style: text.headlineSmall),
              const SizedBox(height: SahlhaSpacing.sm),
              Text(
                'Ask your teacher for the code. It looks like K7P2MQ9A.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: SahlhaSpacing.xl),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: const InputDecoration(
                  labelText: 'Classroom code',
                  hintText: 'Enter code',
                  helperText: 'Letters and numbers only',
                ),
                onSubmitted: (_) => _join(),
              ),
              const SizedBox(height: SahlhaSpacing.xl),
              SahlhaPrimaryButton(
                label: 'Join',
                loading: _busy,
                onPressed: _join,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
