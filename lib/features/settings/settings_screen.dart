import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_theme.dart';
import '../../core/constants/app_typography.dart';
import '../../core/state/settings_controller.dart';
import '../../core/state/morning_checkin_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/utils/navigation.dart';
import '../../core/widgets/app_switch.dart';
import '../../core/widgets/pressable_scale.dart';
import '../band/band_detail_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final checkins = context.watch<MorningCheckinController>();

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.screenPaddingH,
          AppTheme.spaceM,
          AppTheme.screenPaddingH,
          AppTheme.spaceXxxl,
        ),
        children: [
          Text('Settings', style: AppTypography.titleL()),
          const SizedBox(height: AppTheme.spaceXxl),
          Text('REMINDERS', style: AppTypography.labelS()),
          const SizedBox(height: AppTheme.spaceM),
          _SettingsGroup(
            children: [
              _SettingsRow(
                title: 'Morning check-in',
                subtitle: 'The single 9am prompt to rate how you feel.',
                trailing: AppSwitch(
                  value: checkins.enabled,
                  onChanged: (value) {
                    if (!checkins.busy) checkins.setEnabled(value);
                  },
                  semanticLabel: 'Morning check-in notification',
                ),
              ),
              _SettingsRow(
                title: 'Haptic feedback',
                subtitle: 'A light tap when you select something in the app.',
                trailing: AppSwitch(
                  value: settings.hapticsEnabled,
                  onChanged: settings.setHapticsEnabled,
                  semanticLabel: 'In-app haptic feedback',
                ),
              ),
            ],
          ),
          if (checkins.error != null) ...[
            const SizedBox(height: AppTheme.spaceM),
            Text(
              checkins.error!,
              style: AppTypography.bodyS(color: AppColors.textSecondary),
            ),
            PressableScale(
              onTap: openAppSettings,
              semanticLabel: 'Open notification settings',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceM),
                child: Text(
                  'Open phone settings',
                  style: AppTypography.labelL(),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppTheme.spaceXxxl),
          Text('DEVICE', style: AppTypography.labelS()),
          const SizedBox(height: AppTheme.spaceM),
          _SettingsGroup(
            children: [
              _SettingsRow(
                title: 'Manage band',
                subtitle: 'Connection, battery, and pairing.',
                trailing: const Icon(
                  AppIcons.chevronForward,
                  size: AppTheme.iconS,
                  color: AppColors.textMuted,
                ),
                onTap: () => pushOnce(context, (_) => const BandDetailScreen()),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceXxxl),
          Text('ABOUT', style: AppTypography.labelS()),
          const SizedBox(height: AppTheme.spaceM),
          _SettingsGroup(
            children: [
              _SettingsRow(
                title: 'Version',
                trailing: const _AppVersionLabel(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, color: AppColors.bgHairline),
          ],
        ],
      ),
    );
  }
}

class _AppVersionLabel extends StatelessWidget {
  const _AppVersionLabel();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final label = info == null
            ? ''
            : '${info.version} (${info.buildNumber})';
        return Text(label, style: AppTypography.bodyM());
      },
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spaceL,
        vertical: AppTheme.spaceM,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyL()),
                if (subtitle != null) ...[
                  const SizedBox(height: AppTheme.spaceHairline),
                  Text(
                    subtitle!,
                    style: AppTypography.bodyS(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spaceM),
          trailing,
        ],
      ),
    );

    if (onTap == null) return content;
    return PressableScale(onTap: onTap, semanticLabel: title, child: content);
  }
}
