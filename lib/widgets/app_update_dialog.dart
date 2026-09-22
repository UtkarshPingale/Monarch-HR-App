import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/theme_controller.dart';

class AppUpdateDialog extends StatelessWidget {
  final String currentVersion;
  final int currentBuild;
  final String newVersion;
  final int newBuild;
  final String title;
  final String releaseNotes;
  final String downloadUrl;
  final bool isForceUpdate;
  final int versionLag;

  const AppUpdateDialog({
    super.key,
    required this.currentVersion,
    required this.currentBuild,
    required this.newVersion,
    required this.newBuild,
    required this.title,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.isForceUpdate,
    this.versionLag = 0,
  });

  Future<void> _launchUpdateUrl(BuildContext context) async {
    if (downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download URL not provided.')),
      );
      return;
    }
    final uri = Uri.parse(downloadUrl);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open download link.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error opening browser for update.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final bgCard = isDark ? const Color(0xFF131722) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF171C23);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final notesBg = isDark ? const Color(0xFF1A1F2C) : const Color(0xFFF0F4FD);
    final borderColor = isDark ? const Color(0xFF262F42) : const Color(0xFFE2E8F0);
    const amberPrimary = Color(0xFFF5A952);
    const amberDark = Color(0xFF451A03);

    return PopScope(
      canPop: !isForceUpdate,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bgCard,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isForceUpdate ? const Color(0xFFFF2A55).withAlpha(120) : borderColor,
              width: isForceUpdate ? 1.8 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? const Color(0x99000000) : const Color(0x1A171C23),
                blurRadius: 28,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header Icon Badge
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isForceUpdate
                        ? [const Color(0xFFFF4D4D), const Color(0xFFE11D48)]
                        : [const Color(0xFFF5A952), const Color(0xFFE08E2E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isForceUpdate ? const Color(0xFFFF2A55) : amberPrimary).withAlpha(80),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    )
                  ],
                ),
                child: Icon(
                  isForceUpdate ? Icons.system_security_update_rounded : Icons.rocket_launch_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),

              const SizedBox(height: 16),

              // Title
              Text(
                title.isNotEmpty ? title : 'New Update Available!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: textPrimary,
                  letterSpacing: -0.4,
                ),
              ),

              if (isForceUpdate) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2A55).withAlpha(isDark ? 35 : 20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF2A55).withAlpha(100)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFE11D48)),
                      const SizedBox(width: 6),
                      Text(
                        versionLag >= 2
                            ? 'Mandatory: Installed app is $versionLag versions behind'
                            : 'Mandatory update to continue using Monarch HR',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFE11D48)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Version Tags Row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2536) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Installed: v$currentVersion',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 14, color: amberPrimary),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: amberPrimary.withAlpha(35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: amberPrimary.withAlpha(100)),
                    ),
                    child: Text(
                      'Latest: v$newVersion',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: amberPrimary),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Release Notes Container
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "WHAT'S NEW",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: notesBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    releaseNotes.isNotEmpty
                        ? releaseNotes
                        : '• Performance improvements\n• Bug fixes and stability enhancements',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: textPrimary,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              // Action Buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _launchUpdateUrl(context),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    isForceUpdate ? 'Update Now (Required)' : 'Download & Update Now',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isForceUpdate ? const Color(0xFFE11D48) : amberPrimary,
                    foregroundColor: isForceUpdate ? Colors.white : amberDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                    shadowColor: amberPrimary.withAlpha(80),
                  ),
                ),
              ),

              if (!isForceUpdate) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Remind Me Later',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
