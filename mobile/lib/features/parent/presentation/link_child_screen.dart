import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../data/parent_repository.dart';

class LinkChildScreen extends ConsumerStatefulWidget {
  const LinkChildScreen({super.key});

  @override
  ConsumerState<LinkChildScreen> createState() => _LinkChildScreenState();
}

class _LinkChildScreenState extends ConsumerState<LinkChildScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(parentRepositoryProvider).linkChild(code);
      ref.invalidate(linkedChildrenProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Child linked.')));
        context.go('/parent/home');
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
      appBar: const SahlhaAppBar(title: 'Link a child'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter the link code', style: text.headlineSmall),
              const SizedBox(height: SahlhaSpacing.sm),
              Text(
                'Your child finds this 8-letter code in the Sahlha app under Profile. No IDs to type.',
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
                  labelText: 'Link code',
                  hintText: 'Enter code',
                ),
                onSubmitted: (_) => _link(),
              ),
              const SizedBox(height: SahlhaSpacing.xl),
              SahlhaPrimaryButton(
                label: 'Link child',
                loading: _busy,
                onPressed: _link,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
