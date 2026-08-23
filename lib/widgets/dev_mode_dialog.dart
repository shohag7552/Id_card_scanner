import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

/// Developer-mode UI helpers.
///
/// In [AppMode.dev] the app shows a notice before every ID scan (so testers
/// know it is a development build and that paid AI models are disabled). In
/// [AppMode.release] these helpers are no-ops that let the flow proceed
/// silently — so call sites don't need their own mode checks.
class DevModeDialog {
  const DevModeDialog._();

  /// Shows the "developer build" notice before a scan and resolves to whether
  /// the user chose to continue. Returns `true` immediately (no dialog) when
  /// the app is in release mode, so existing behaviour is unchanged there.
  static Future<bool> confirmScan(BuildContext context) async {
    if (!AppConstants.isDevMode) return true;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.borderCol),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.accentGold.withAlpha(38),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.construction,
                  color: AppTheme.accentGold, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Developer Mode',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'This is a development build.\n\n'
          '• Paid (Pro-tier) AI models are disabled — only free models run.\n'
          '• Set AppConstants.appMode to release for full functionality.\n\n'
          'Continue scanning with a free model?',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    return proceed ?? false;
  }
}
