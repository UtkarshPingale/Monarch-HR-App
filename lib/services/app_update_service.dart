import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../widgets/app_update_dialog.dart';

class AppUpdateService {
  // Current app release version & build number (matching pubspec.yaml: 1.0.0+4)
  static const String currentVersionName = "1.0.0";
  static const int currentVersionCode = 4;

  static bool _hasShownThisSession = false;

  /// Compares version string or version code and shows dialog if update available
  static Future<bool> checkForUpdates(
    BuildContext context, {
    bool silent = true,
  }) async {
    try {
      final res = await apiGetJson('/api/app/version');
      if (res is Map<String, dynamic>) {
        final newVersionName = res['version_name']?.toString() ?? '1.0.0';
        final newVersionCode = int.tryParse(res['version_code']?.toString() ?? '0') ?? 0;
        final downloadUrl = res['download_url']?.toString() ?? '';
        final releaseNotes = res['release_notes']?.toString() ?? '';
        final title = res['title']?.toString() ?? 'Monarch HR Update Available!';
        final isForceUpdate = res['is_force_update'] == true;

        final bool hasNewerBuild = newVersionCode > currentVersionCode;
        final bool hasNewerVersion = _isVersionNewer(newVersionName, currentVersionName);

        final bool isUpdateAvailable = hasNewerBuild || hasNewerVersion;

        if (isUpdateAvailable) {
          if (!silent || !_hasShownThisSession || isForceUpdate) {
            _hasShownThisSession = true;
            if (context.mounted) {
              showDialog(
                context: context,
                barrierDismissible: !isForceUpdate,
                builder: (_) => AppUpdateDialog(
                  currentVersion: currentVersionName,
                  currentBuild: currentVersionCode,
                  newVersion: newVersionName,
                  newBuild: newVersionCode,
                  title: title,
                  releaseNotes: releaseNotes,
                  downloadUrl: downloadUrl,
                  isForceUpdate: isForceUpdate,
                ),
              );
            }
          }
          return true;
        } else {
          if (!silent && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ You are on the latest version of Monarch HR.'),
                backgroundColor: Color(0xFF1B7047),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return false;
        }
      }
    } catch (_) {
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠ Unable to check for updates. Check connection.'),
            backgroundColor: Color(0xFFBA1A1A),
          ),
        );
      }
    }
    return false;
  }

  /// Helper to compare semver like "1.0.5" vs "1.0.4"
  static bool _isVersionNewer(String remote, String local) {
    try {
      final rParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final lParts = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      while (rParts.length < 3) {
        rParts.add(0);
      }
      while (lParts.length < 3) {
        lParts.add(0);
      }
      for (int i = 0; i < 3; i++) {
        if (rParts[i] > lParts[i]) return true;
        if (rParts[i] < lParts[i]) return false;
      }
    } catch (_) {}
    return false;
  }
}
