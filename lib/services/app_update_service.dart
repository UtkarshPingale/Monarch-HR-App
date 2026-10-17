import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_update/in_app_update.dart';
import '../config/api_config.dart';

class AppUpdateService {
  // Current app release version & build number (dynamically resolved from device package info)
  static String _currentVersionName = "1.0.6";
  static int _currentVersionCode = 14;
  static bool _initialized = false;

  static String get currentVersionName => _currentVersionName;
  static int get currentVersionCode => _currentVersionCode;

  /// Initializes version and build number directly from native platform metadata
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        _currentVersionName = info.version;
      }
      final bn = int.tryParse(info.buildNumber);
      if (bn != null && bn > 0) {
        _currentVersionCode = bn;
      }
      _initialized = true;

      // Check if a background flexible Play Store update finished downloading
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final updateInfo = await InAppUpdate.checkForUpdate();
          if (updateInfo.installStatus == InstallStatus.downloaded) {
            await InAppUpdate.completeFlexibleUpdate();
          }
        } catch (_) {}
      }
    } catch (_) {
      // Fallback to default constants if platform channel fails
    }
  }

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

  /// Silently checks if an update is available without opening any dialogs or snackbars
  static Future<bool> isUpdateAvailable() async {
    try {
      await init();
      final String platform = (!kIsWeb && Platform.isIOS) ? 'ios' : 'android';
      final res = await apiGetJson('/api/app/version?platform=$platform');
      if (res is Map<String, dynamic>) {
        final newVersionName = res['version_name']?.toString() ?? '1.0.0';
        final newVersionCode = int.tryParse(res['version_code']?.toString() ?? '0') ?? 0;

        final int versionLag = calculateVersionLag(
          newVersionName,
          currentVersionName,
          newVersionCode,
          currentVersionCode,
        );

        final bool hasNewerBuild = newVersionCode > currentVersionCode;
        final bool hasNewerVersion = _isVersionNewer(newVersionName, currentVersionName);
        return hasNewerBuild || hasNewerVersion || versionLag > 0;
      }
    } catch (_) {}
    return false;
  }

  static const String playStorePackage = 'com.monarchconsultants.monarchhr';
  static const String playStoreMarketUrl = 'market://details?id=$playStorePackage';
  static const String playStoreWebUrl = 'https://play.google.com/store/apps/details?id=$playStorePackage';

  static const String appStoreWebUrl = 'https://apps.apple.com/app/monarch-hr/id6815123696';
  static const String appStoreSchemeUrl = 'itms-apps://apps.apple.com/app/monarch-hr/id6815123696';

  /// Directly opens the target platform store (Google Play Store for Android, Apple App Store for iOS)
  static Future<void> openStore({
    BuildContext? context,
    String? customUrl,
    String? playStoreUrl,
    String? appStoreUrl,
  }) async {
    final bool isIos = !kIsWeb && Platform.isIOS;

    if (isIos) {
      final String iosTarget = (appStoreUrl ?? customUrl ?? '').trim();
      if (iosTarget.isNotEmpty && (iosTarget.contains('apple.com') || iosTarget.startsWith('itms-apps://'))) {
        try {
          final uri = Uri.parse(iosTarget);
          if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            return;
          }
        } catch (_) {}
      }
      try {
        final schemeUri = Uri.parse(appStoreSchemeUrl);
        if (await canLaunchUrl(schemeUri)) {
          await launchUrl(schemeUri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
      try {
        final webUri = Uri.parse(appStoreWebUrl);
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return;
      } catch (_) {
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Apple App Store.')),
          );
        }
      }
      return;
    }

    // Android / Default
    final String target = (playStoreUrl ?? customUrl ?? '').trim();
    if (target.toLowerCase().endsWith('.apk')) {
      try {
        final uri = Uri.parse(target);
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {}
    }

    try {
      final marketUri = Uri.parse(playStoreMarketUrl);
      if (await canLaunchUrl(marketUri)) {
        await launchUrl(marketUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    try {
      final webUri = Uri.parse(target.isNotEmpty && target.contains('play.google.com') ? target : playStoreWebUrl);
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Play Store.')),
        );
      }
    }
  }

  /// Backward compatible alias for openStore
  static Future<void> openPlayStore({BuildContext? context, String? customUrl}) async {
    await openStore(context: context, customUrl: customUrl);
  }

  /// Directly calls the Google Play In-App Updates API (Immediate or Flexible).
  /// Works natively on Android devices when the app is installed from Google Play.
  /// Returns true if an update was found and successfully triggered.
  static Future<bool> performPlayStoreInAppUpdate({bool immediate = true}) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final AppUpdateInfo info = await InAppUpdate.checkForUpdate();

      // If a flexible update was previously downloaded, install and restart
      if (info.installStatus == InstallStatus.downloaded) {
        await InAppUpdate.completeFlexibleUpdate();
        return true;
      }

      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (immediate && info.immediateUpdateAllowed) {
          final result = await InAppUpdate.performImmediateUpdate();
          return result == AppUpdateResult.success;
        } else if (info.flexibleUpdateAllowed) {
          final result = await InAppUpdate.startFlexibleUpdate();
          if (result == AppUpdateResult.success) {
            await InAppUpdate.completeFlexibleUpdate();
            return true;
          }
        } else if (info.immediateUpdateAllowed) {
          final result = await InAppUpdate.performImmediateUpdate();
          return result == AppUpdateResult.success;
        }
      }
    } catch (e) {
      debugPrint('[PlayStoreInAppUpdate] Skipped or not applicable: $e');
    }
    return false;
  }

  /// Checks for updates.
  /// 1. Tries Google Play In-App Update API directly on Android.
  /// 2. If running outside Play Store (sideloaded, iOS, or dev), checks /api/app/version and prompts.
  static Future<bool> checkForUpdates(
    BuildContext context, {
    bool silent = true,
    bool preferImmediate = true,
  }) async {
    // 1. First attempt Google Play Store In-App Update on Android
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool playHandled = await performPlayStoreInAppUpdate(immediate: preferImmediate);
        if (playHandled) return true;
      } catch (_) {}
    }

    // 2. Fallback to API check (/api/app/version) for iOS, Sideloaded APK, or Dev Builds
    try {
      await init();
      final String platform = (!kIsWeb && Platform.isIOS) ? 'ios' : 'android';
      final res = await apiGetJson('/api/app/version?platform=$platform');
      if (res is Map<String, dynamic>) {
        final newVersionName = res['version_name']?.toString() ?? '1.0.0';
        final newVersionCode = int.tryParse(res['version_code']?.toString() ?? '0') ?? 0;
        final downloadUrl = res['download_url']?.toString() ?? '';
        final playStoreUrl = res['play_store_url']?.toString() ?? '';
        final appStoreUrl = res['app_store_url']?.toString() ?? '';
        final isForceUpdate = res['is_force_update'] == true;

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
          if (context.mounted) {
            if (isForceUpdate) {
              await _showMandatoryUpdateDialog(
                context,
                newVersionName: newVersionName,
                releaseNotes: res['release_notes']?.toString(),
                onUpdate: () => openStore(
                  context: context,
                  customUrl: downloadUrl,
                  playStoreUrl: playStoreUrl,
                  appStoreUrl: appStoreUrl,
                ),
              );
            } else if (!silent) {
              await openStore(
                context: context,
                customUrl: downloadUrl,
                playStoreUrl: playStoreUrl,
                appStoreUrl: appStoreUrl,
              );
            }
          }
          return true;
        } else {
          if (!silent && context.mounted) {
            final messenger = ScaffoldMessenger.of(context);
            messenger.removeCurrentSnackBar();
            messenger.clearSnackBars();
            messenger.showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Monarch HR v$currentVersionName (Build $currentVersionCode) is up to date!',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF1B7047),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                dismissDirection: DismissDirection.horizontal,
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

  /// Displays an un-dismissible popup when a force update is configured on the backend
  static Future<void> _showMandatoryUpdateDialog(
    BuildContext context, {
    required String newVersionName,
    String? releaseNotes,
    required VoidCallback onUpdate,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.system_update_rounded, color: Color(0xFFF5A952), size: 28),
                SizedBox(width: 10),
                Text('Update Required', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A critical update to Monarch HR (v$newVersionName) is required to continue.',
                  style: const TextStyle(fontSize: 14),
                ),
                if (releaseNotes != null && releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('What\'s new:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(releaseNotes, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5A952),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: onUpdate,
                child: const Text('Update Now', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
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
