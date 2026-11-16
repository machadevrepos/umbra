import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_theme.dart';
import '../../core/constants/app_typography.dart';
import '../../core/state/band_controller.dart';
import '../../core/utils/band_status_presentation.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/navigation.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/labeled_stat.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/widgets/status_chip.dart';
import '../onboarding/band_pairing_screen.dart';
import 'widgets/forget_band_sheet.dart';

class BandDetailScreen extends StatelessWidget {
  const BandDetailScreen({super.key});
  Future<void> _action(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The band did not confirm the command. Reconnect and try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final band = context.watch<BandController>();
    final status = BandStatusPresentation.of(band.state);
    final oxygen = band.spo2Reading;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.screenPaddingH),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PressableScale(
                onTap: () => Navigator.of(context).pop(),
                semanticLabel: 'Back',
                child: const SizedBox(
                  width: AppTheme.minTapTarget,
                  height: AppTheme.minTapTarget,
                  child: Icon(
                    AppIcons.chevronBack,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceL),
            Text(band.deviceName, style: AppTypography.titleL()),
            const SizedBox(height: AppTheme.spaceM),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusChip(
                label: status.label,
                icon: status.icon,
                color: status.color,
                tint: AppColors.bgHairline,
              ),
            ),
            const SizedBox(height: AppTheme.spaceXxl),
            Row(
              children: [
                Expanded(
                  child: LabeledStat(
                    label: 'Heart rate',
                    value: band.heartRate == null
                        ? 'No reading'
                        : '${band.heartRate} bpm',
                  ),
                ),
                Expanded(
                  child: LabeledStat(
                    label: 'Battery',
                    value: band.battery < 0 ? 'No data' : '${band.battery}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceL),
            LabeledStat(
              label: 'Steps since power-on',
              value: band.steps == null ? 'No data' : '${band.steps}',
            ),
            const SizedBox(height: AppTheme.spaceS),
            Text(
              band.steps == null
                  ? 'Connect your band to read and save its step count.'
                  : band.connected &&
                        band.configurationReady &&
                        band.stepsAt != null
                  ? 'Counted by your band. Saved on this phone; resets when the band powers on.'
                  : 'Last saved count. Reconnect your band for the current reading.',
              style: AppTypography.bodyS(),
            ),
            if (band.readingIssue != null) ...[
              const SizedBox(height: AppTheme.spaceM),
              Text(band.readingIssue!, style: AppTypography.bodyS()),
            ],
            const SizedBox(height: AppTheme.spaceL),
            Text(
              'Firmware: ${band.firmwareVersion ?? 'Not read yet'}',
              style: AppTypography.bodyS(),
            ),
            if (!band.connected && band.lastSeenAt != null)
              Text(
                'Last seen ${relativeTimeAgoLabel(band.lastSeenAt!)}. Battery is cached.',
                style: AppTypography.bodyS(),
              ),
            const SizedBox(height: AppTheme.spaceXxxl),
            Text('Blood oxygen', style: AppTypography.titleM()),
            const SizedBox(height: AppTheme.spaceS),
            Text(
              oxygen?.percent == null
                  ? 'No reading yet'
                  : '${oxygen!.percent}%${oxygen.measuredAt == null ? ' (time unavailable)' : ' measured ${relativeTimeAgoLabel(oxygen.measuredAt!)}'}',
              style: AppTypography.bodyL(),
            ),
            if (oxygen != null) ...[
              const SizedBox(height: AppTheme.spaceS),
              Text(
                '${oxygen.statusLabel} Quality ${oxygen.quality}/100.',
                style: AppTypography.bodyS(),
              ),
            ],
            const SizedBox(height: AppTheme.spaceL),
            AppButton(
              label: oxygen?.status == 2
                  ? 'Measuring on your band'
                  : 'Measure SpO2',
              onTap: band.canControl && oxygen?.status != 2
                  ? () => _action(context, band.measureSpo2)
                  : null,
            ),
            const SizedBox(height: AppTheme.spaceM),
            Text(
              'Keep your wrist still for about 35 seconds. This is a wellness estimate.',
              style: AppTypography.bodyS(),
            ),
            const SizedBox(height: AppTheme.spaceXl),
            AppButton(
              label: 'Test band vibration',
              variant: AppButtonVariant.secondary,
              onTap: band.canControl
                  ? () => _action(context, band.triggerHaptic)
                  : null,
            ),
            if (band.deviceError != null) ...[
              const SizedBox(height: AppTheme.spaceL),
              Text(band.deviceError!, style: AppTypography.bodyM()),
            ],
            const SizedBox(height: AppTheme.spaceXxxl),
            Text(
              'Your band keeps its reminders and records running without the app.',
              style: AppTypography.bodyM(),
            ),
            const SizedBox(height: AppTheme.spaceXl),
            AppButton(
              label: band.connected ? 'Reconnect band' : 'Reconnect',
              variant: AppButtonVariant.secondary,
              onTap: band.connected
                  ? () => _action(context, band.retryInitialization)
                  : () => pushOnce(
                      context,
                      (_) => const BandPairingScreen(onboarding: false),
                    ),
            ),
            if (band.deviceId != null) ...[
              const SizedBox(height: AppTheme.spaceM),
              AppButton(
                label: 'Forget this band',
                variant: AppButtonVariant.secondary,
                onTap: () async {
                  if (await showForgetBandSheet(context)) await band.forget();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
