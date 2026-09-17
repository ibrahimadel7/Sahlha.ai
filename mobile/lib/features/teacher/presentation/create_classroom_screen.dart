import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../classrooms/data/classroom_repository.dart';

class CreateClassroomScreen extends ConsumerStatefulWidget {
  const CreateClassroomScreen({super.key});

  @override
  ConsumerState<CreateClassroomScreen> createState() =>
      _CreateClassroomScreenState();
}

class _CreateClassroomScreenState extends ConsumerState<CreateClassroomScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _subject = TextEditingController();
  final _grade = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _subject.dispose();
    _grade.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final room = await ref
          .read(classroomRepositoryProvider)
          .create(
            name: _name.text.trim(),
            subject: _subject.text.trim(),
            gradeLevel: _grade.text.trim(),
          );
      ref.invalidate(classroomListProvider);
      if (mounted) context.go('/teacher/classrooms/${room.id}');
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
      appBar: const SahlhaAppBar(title: 'New Classroom'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Create a classroom', style: text.headlineSmall),
                const SizedBox(height: SahlhaSpacing.sm),
                Text(
                  'You’ll get a short join code to share with your students.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: SahlhaSpacing.xl),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Classroom name',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: SahlhaSpacing.md),
                TextFormField(
                  controller: _subject,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    hintText: 'Math, Science, English…',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: SahlhaSpacing.md),
                TextFormField(
                  controller: _grade,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Grade level',
                    hintText: 'Grade 5',
                  ),
                ),
                const SizedBox(height: SahlhaSpacing.xl),
                SahlhaPrimaryButton(
                  label: 'Create classroom',
                  loading: _busy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
