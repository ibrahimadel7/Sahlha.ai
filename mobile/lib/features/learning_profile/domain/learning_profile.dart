import 'package:freezed_annotation/freezed_annotation.dart';

part 'learning_profile.freezed.dart';
part 'learning_profile.g.dart';

/// How Sahlha should currently support the student. Support preferences only —
/// never medical. `linkCode` is included for the student (parent linking).
@freezed
abstract class LearningProfile with _$LearningProfile {
  const factory LearningProfile({
    @JsonKey(name: 'onboarding_completed')
    @Default(false)
    bool onboardingCompleted,
    @Default({}) Map<String, String> supports,
    @Default({}) Map<String, dynamic> observed,
    @JsonKey(name: 'support_summary') @Default([]) List<String> supportSummary,
    @JsonKey(name: 'link_code') @Default('') String linkCode,
  }) = _LearningProfile;

  factory LearningProfile.fromJson(Map<String, dynamic> json) =>
      _$LearningProfileFromJson(json);
}

/// One onboarding question (one question at a time in the UI).
class ProfileStep {
  const ProfileStep({
    required this.key,
    required this.title,
    required this.options,
  });

  final String key;
  final String title;
  final List<ProfileOption> options;
}

class ProfileOption {
  const ProfileOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// Short, accessible onboarding. Friendly support language only.
const List<ProfileStep> kProfileSteps = [
  ProfileStep(
    key: 'reading',
    title: 'How is reading long lessons for you?',
    options: [
      ProfileOption(value: 'easy', label: 'Easy for me'),
      ProfileOption(value: 'sometimes', label: 'Sometimes hard'),
      ProfileOption(value: 'hard', label: 'Often hard'),
    ],
  ),
  ProfileStep(
    key: 'focus',
    title: 'How long can you focus comfortably?',
    options: [
      ProfileOption(value: 'long', label: 'A long time'),
      ProfileOption(value: 'medium', label: 'A little while'),
      ProfileOption(value: 'short', label: 'Short bursts'),
    ],
  ),
  ProfileStep(
    key: 'instructions',
    title: 'How do you like instructions?',
    options: [
      ProfileOption(value: 'long_ok', label: 'All at once is fine'),
      ProfileOption(value: 'steps', label: 'One step at a time'),
      ProfileOption(value: 'show_first', label: 'Show me an example first'),
    ],
  ),
  ProfileStep(
    key: 'presentation',
    title: 'What helps you understand best?',
    options: [
      ProfileOption(value: 'read', label: 'Reading'),
      ProfileOption(value: 'listen', label: 'Listening'),
      ProfileOption(value: 'pictures', label: 'Pictures'),
    ],
  ),
  ProfileStep(
    key: 'practice',
    title: 'How do you like to practice?',
    options: [
      ProfileOption(value: 'try_first', label: 'Let me try first'),
      ProfileOption(value: 'example_first', label: 'Example first, then I try'),
      ProfileOption(value: 'practice_more', label: 'Lots of practice'),
    ],
  ),
  ProfileStep(
    key: 'session',
    title: 'How long should a learning session be?',
    options: [
      ProfileOption(value: 'short', label: 'Short'),
      ProfileOption(value: 'medium', label: 'Medium'),
      ProfileOption(value: 'long', label: 'Long'),
    ],
  ),
  ProfileStep(
    key: 'confidence',
    title: 'How do you feel about learning new things?',
    options: [
      ProfileOption(value: 'confident', label: 'Confident'),
      ProfileOption(value: 'sometimes', label: 'Sometimes unsure'),
      ProfileOption(value: 'nervous', label: 'Often unsure'),
    ],
  ),
];
