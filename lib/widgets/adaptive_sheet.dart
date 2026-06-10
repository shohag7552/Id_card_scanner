import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Width at/above which the layout is considered "big screen" (web / desktop /
/// tablet) and bottom sheets are presented as centered dialogs instead.
const double kAdaptiveSheetBreakpoint = 600;

/// Presents [builder]'s content as a modal bottom sheet on mobile-width layouts,
/// or as a centered dialog on web / big screens.
///
/// The same [builder] is reused for both, so callers just supply the sheet body
/// (typically a `SafeArea` + `Column` of `ListTile`s) and the surrounding
/// chrome — rounded corners, surface colour, scrolling — is applied here.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  final isBigScreen =
      MediaQuery.of(context).size.width >= kAdaptiveSheetBreakpoint;

  if (isBigScreen) {
    return showDialog<T>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: AppTheme.surfaceBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.borderCol),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: builder(context),
            ),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: AppTheme.surfaceBg,
    isScrollControlled: isScrollControlled,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: builder,
  );
}
