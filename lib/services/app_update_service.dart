import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../widgets/app_update_dialog.dart';

class AppUpdateService {
  // Current app release version & build number (matching pubspec.yaml: 1.0.2+6)
  static const String currentVersionName = "1.0.2";
  static const int currentVersionCode = 6;

  static bool _hasShownThisSession = false;

  /// Calculates how many versions behind the local app is relative to remote.
  /// E.g. local 1.0.0 vs remote 1.0.2 -> 2 versions behind
  /// E.g. local 1.0.1 vs remote 1.0.4 -> 3 versions behind
  static int calculateVersionLag(String remote, String local, int remoteBuild, int localBuild) {
    try {
      final rParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final lParts = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      while (rParts.length < 3) {
        rParts.add(0);
      }
      while (lParts.length < 3) {
        lParts.add(0);
      }

      // Major version difference (e.g. 2.0 vs 1.0) -> >= 10 lag
      if (rParts[0] > lParts[0]) {
        return ((rParts[0] - lParts[0]) * 10) + (rParts[1] - lParts[1]);
      }
      // Minor version difference (e.g. 1.3 vs 1.0)
      if (rParts[1] > lParts[1]) {
        return ((rParts[1] - lParts[1]) * 3) + (rParts[2] - lParts[2]);
      }
      // Patch version difference (e.g. 1.0.4 vs 1.0.2 -> 2 versions behind)
      if (rParts[2] > lParts[2]) {
        return rParts[2] - lParts[2];
      }
      // Build code difference fallback (e.g. Build 9 vs Build 6 -> 3 builds behind)
      if (remoteBuild > localBuild) {
        return remoteBuild - localBuild;
      }
    } catch (_) {}
    return 0;
  }

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

        final int versionLag = calculateVersionLag(
          newVersionName,
          currentVersionName,
          newVersionCode,
          currentVersionCode,
        );

        final bool hasNewerBuild = newVersionCode > currentVersionCode;
        final bool hasNewerVersion = _isVersionNewer(newVersionName, currentVersionName);
        final bool isUpdateAvailable = hasNewerBuild || hasNewerVersion || versionLag > 0;

        if (isUpdateAvailable) {
          if (!silent || !_hasShownThisSession) {
            _hasShownThisSession = true;
            if (context.mounted) {
              showDialog(
                context: context,
                barrierDismissible: true,
                builder: (_) => AppUpdateDialog(
                  currentVersion: currentVersionName,
                  currentBuild: currentVersionCode,
                  newVersion: newVersionName,
                  newBuild: newVersionCode,
                  title: title,
                  releaseNotes: releaseNotes,
                  downloadUrl: downloadUrl,
                  isForceUpdate: false,
                  versionLag: versionLag,
                ),
              );
            }
          }
          return true;
        } else {
          if (!silent && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'App is up to date! Monarch HR v$currentVersionName (Build $currentVersionCode) is the latest release.',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF1B7047),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            );
          }
          return false;
        }
      }
    } catch (_) {
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Unable to check for updates. Check connection.'),
              ],
            ),
            backgroundColor: const Color(0xFFBA1A1A),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
