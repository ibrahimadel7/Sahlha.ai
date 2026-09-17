# UI review and follow-up plan

Reviewed: 2026-09-15. Scope: all 29 screen source files, the route definitions,
shared app bar and navigation shell, and the controllers supporting their actions.
This is a code review and test plan. DevicePreview screenshots of every screen,
live accounts, and physical-device interactions have not been exercised in this review.

## Completed: material → classroom navigation

- Successful upload replaces the upload form with the material page while keeping
  the classroom underneath it.
- The material app bar always has a back button. Existing navigation history is
  used first, preserving the classroom's selected tab and scroll state.
- A directly opened material uses its loaded classroom ID to return to that
  classroom's Materials tab. The upload URL carries a classroom hint for loading
  or error states. With neither history nor a known classroom, back opens Classes.
- A directly opened classroom also has a back button to Classes.
- The material page handles a blocked system-back action with the same fallback.

Regression tests: `mobile/test/material_navigation_test.dart` covers existing
materials, successful uploads, direct material links, and failed material loading.

## Priority 1: navigation, recovery, and consistent data

| Finding | Evidence and reproduction | Planned change | Acceptance check |
|---|---|---|---|
| Confirmed: malformed lesson URL can throw | `app/router.dart` force-unwraps `materialId` for `/student/skill/:skillId`. Open that URL without the query parameter. | Validate required route arguments; show an explanatory page with a return action. | Missing/empty material ID, unknown ID, and wrong-role URLs never produce an uncaught exception. |
| Confirmed: practice retry exits | `practice_screen.dart` passes `context.pop()` as the error screen's retry action. | Retry `start()` with the original scope; provide a separate back action with a fallback. | Start fails once, retry succeeds on the same screen; a direct link can still leave safely. |
| Confirmed: empty practice response has no exit UI | When `state.current` is null, practice renders only a spinner. | Show a no-approved-questions state with an exit action and optional retry. | A successful response containing zero questions terminates loading. |
| Confirmed: other detail pages still rely on automatic back arrows | Bank review, student detail, lesson, join, and link screens use a shared app bar without a fallback. Their routes are top-level siblings. | Define an appropriate parent destination for each route; preserve push history during normal navigation. | App-bar back, Android back, browser back, refresh, and direct links have deliberate outcomes. |
| Confirmed: parent library selection can disagree with results | `child_materials_screen.dart` prioritizes constructor `childId` over selected-child state, while the dropdown only changes selected-child state. Open `/parent/materials?childId=A`, then choose B. | Use one validated selection source and update the URL or local selection consistently. | Dropdown, cards, upload target, and progress all refer to B; removed children recover to a valid selection. |
| Likely: material approval badges remain stale after review | Material bank cards push review without awaiting a result or invalidating the material bank provider. Review refreshes its own detail provider. | Return a mutation result or invalidate all affected material, classroom, and dashboard queries after review changes. | Approve/reject/delete in review, return, and see updated counts/status without manual refresh. |
| Confirmed: transient startup failure clears login | `auth_controller.dart` clears the token for every `/auth/me` exception, including connection failures. Bootstrap awaits auth before showing the app. | Distinguish invalid-session responses from offline/timeouts; render a startup recovery screen. | Offline launch offers retry; a confirmed invalid token signs out; no unexplained blank startup wait. |
| Likely: student home stays stale after joining | `join_classroom_screen.dart` invalidates classroom list only; home uses `studentHomeProvider`. | Invalidate membership-dependent home/path/progress queries after joining. | Visit Home, join a class, return, and see it immediately. |

## Priority 2: responsive layouts and action safety

| Finding | Evidence | Planned change and test |
|---|---|---|
| Likely overflow on small devices or large text | Role selection and learning-profile setup use fixed vertical columns with spacers; join/link forms are not scrollable. Login/register footer text is in a single row. | Use scrollable constrained layouts and wrapping text. Test portrait, landscape, visible keyboard, and 200% text size. |
| Confirmed: missing profile error UI | Student profile uses `whenOrNull(data: ...)` for link-code information, so errors hide the card. | Show loading, failure, and retry in the card; distinguish an absent code from unavailable data. |
| Confirmed: raw internal IDs shown as question-bank titles | `material_detail_screen.dart` renders `bank.skillId`; the supplied screenshot shows generated ID prefixes. | Resolve the matching skill's display name, retaining the ID only as a fallback. Test long names and duplicate names. |
| Likely late async updates after leaving screens | Practice controller changes state after requests without mounted checks. Bank review invalidates through `ref` after awaiting actions, and schedules a `setState` callback without a mounted guard. | Guard completion after disposal; keep necessary background work separate from screen state. Test back/logout while each request is pending. |
| Likely duplicate form submission | Login/register keyboard submission calls `_submit` even while loading; several submit methods have no busy guard. | Gate methods as well as buttons; keep one request active. Test Enter twice, rapid taps, and slow responses. |
| Confirmed: supplementary practice loses its return context | Practice result navigation returns to classroom learning or unscoped learning; supplementary context is not passed to the result view. | Carry the practice scope to completion and return to Extra Practice when appropriate. |
| Confirmed: empty bank recovery is only text | Bank review's zero-question state says to regenerate but provides no action. | Provide a working regeneration/return-to-material action and prevent approving empty banks. |
| Needs device verification: protected audio/image loading | Lesson audio passes auth headers to the player; media behavior varies by target. | Exercise browser and Android playback, expired auth, unavailable providers, image failures, and leaving during playback. Preserve text learning when media fails. |

## Every-screen checklist

“Risk” below identifies a case to reproduce, not a claim that the screen has
already failed in a running app. Rows also cover dialogs and nested tabs belonging
to that screen.

| Screen/source basename | Main check or expected failure | Priority |
|---|---|---|
| `splash_screen.dart` | Slow/offline session restoration, sign-in redirect, repeat onboarding policy. | 1 |
| `onboarding_screen.dart` | Slide text fits landscape/large text; rapid Next taps; login shortcut. | 2 |
| `choose_role_screen.dart` | Three role cards and actions fit small heights; return from login/register to change role. | 2 |
| `login_screen.dart` | Offline/invalid credentials, keyboard double submission, footer wrapping, role change. | 1–2 |
| `register_screen.dart` | Duplicate email, invalid role query, double submission, successful student setup redirect. | 1–2 |
| `learning_profile_screen.dart` | Each step at large text size; back follows steps; submission pending while navigating away. | 2 |
| `student_home_screen.dart` | Refresh after joining/submitting; profile fetch errors; long names and empty curriculum. | 1–2 |
| `join_classroom_screen.dart` | Invalid/already-joined code, keyboard coverage, immediate Home refresh, direct-link back. | 1–2 |
| `learn_screen.dart` | Missing/removed classroom, selector/URL consistency, no skills or no approved practice. | 1–2 |
| `skill_lesson_screen.dart` | Required URL data, read-aloud/image errors, help-sheet overflow, lesson return path. | 1–2 |
| `practice_screen.dart` | Start/retry/empty response, unanswered questions, check/submit races, exit mid-attempt, supplementary return. | 1 |
| `student_progress_screen.dart` | Empty grades, zero skills, long unit names, refresh after assessment, correct scope on lesson link. | 2 |
| `student_profile_screen.dart` | Link-code fetch failure/retry/copy feedback, long email, logout failure/repeated taps. | 2 |
| `teacher_dashboard_screen.dart` | Counts refresh after uploads/review; zero classes; long names and narrow stat cards. | 1–2 |
| `classrooms_screen.dart` | Empty/error/retry, last list item above floating action button, return after creating class. | 2 |
| `create_classroom_screen.dart` | Required fields, duplicate submission, pending request after exit, resulting classroom back path. | 2 |
| `classroom_detail_screen.dart` | Students/Materials/Insights empty/error states; keep tab after material return; copy code; long tab content. Back fallback implemented. | 1–2 |
| `material_upload_screen.dart` | Pick/cancel, PDF bytes/native paths, size/error states, missing classroom context, upload replacement. Navigation implemented. | 1–2 |
| `material_detail_screen.dart` | Direct/stack back implemented; bank badges after review, meaningful skill titles, extraction/generation failures, edit sheet. | 1–2 |
| `bank_review_screen.dart` | Back after direct link; approve/reject/edit/delete/regenerate, last question removed, pending action during exit. | 1–2 |
| `student_detail_screen.dart` | Unknown/removed student, no grades, long support summaries, direct-link classroom return. | 1–2 |
| `analytics_screen.dart` | Zero classes/students/skills, removed selected class, long chart labels and large-text tooltips. | 2 |
| `teacher_profile_screen.dart` | Long identity fields, create-classroom return, logout and account switch with cached tabs. | 2 |
| `parent_home_screen.dart` | Selected child removed/changed; selection matches progress; refresh reflects linking. | 1–2 |
| `link_child_screen.dart` | Empty/invalid/already-linked code, visible keyboard, double submission and direct-link return. | 1–2 |
| `child_progress_screen.dart` | Overview/Skills/Activity all refer to selected child; empty states; invalid supplied child ID. | 1–2 |
| `child_materials_screen.dart` | Child dropdown drives the actual list; long filenames; upload return refresh; missing child. | 1 |
| `supplementary_upload_screen.dart` | Valid child required; switching child clears prior material; extraction retry/exit; return to same child's library. | 1–2 |
| `parent_profile_screen.dart` | Link-child return, long identity fields, logout and stale selected-child state after account switch. | 2 |

## Execution order and release checks

1. Navigation and recovery: route validation, detail-screen fallbacks, real retry
   actions, empty practice state. Add route tests for all role entry/exit paths.
2. Data consistency: unify child selection and refresh affected data after upload,
   review, joining, profile update, and assessment submission.
3. Async safety: disable duplicate calls, handle leaving during requests, and
   preserve recoverable authentication failures.
4. Responsive pass in DevicePreview: 320×568, 390×844, landscape 844×390,
   and tablet 768×1024; text scaling 100% and 200%; keyboard open for every form.
5. Verify every row with empty, populated, long-text, loading, offline, 401, 403,
   and 404 states where relevant. Check the existing accessibility labels,
   keyboard focus, and scroll reachability of primary actions.
6. Run Flutter analysis and the regression suite. Check Android system back,
   browser back/refresh, and authenticated media in an actual browser/device;
   DevicePreview alone cannot prove platform behavior.

Done means: no navigation dead ends, no indefinite loading for terminal results,
selected context matches displayed data, and controls remain reachable in the
device matrix. The follow-up items above are planned work, not changes claimed
as completed by this navigation fix.
