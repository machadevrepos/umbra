import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_theme.dart';
import '../../core/constants/app_typography.dart';
import '../../core/state/band_controller.dart';
import '../../core/utils/navigation.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/labeled_stat.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/widgets/status_chip.dart';
import '../onboarding/band_pairing_screen.dart';
import 'widgets/forget_band_sheet.dart';

class BandDetailScreen extends StatelessWidget {
  const BandDetailScreen({super.key});

  Future<void> _forget(BuildContext context, BandController band) async {
    final confirmed = await showForgetBandSheet(context);
    if (confirmed) band.setConnected(false);
  }

  Future<void> _reconnect(BuildContext context) async {
    await pushOnce(context, (_) => const BandPairingScreen());
  }

  @override
  Widget build(BuildContext context) {
    final band = context.watch<BandController>();

    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPaddingH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppTheme.spaceS),
              PressableScale(
                onTap: () => Navigator.of(context).pop(),
                semanticLabel: 'Back',
                child: Container(
                  width: AppTheme.minTapTarget,
                  height: AppTheme.minTapTarget,
                  alignment: Alignment.centerLeft,
                  child: const Icon(AppIcons.chevronBack, size: AppTheme.iconL, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: AppTheme.spaceL),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: band.connected ? AppColors.goldBorder : AppColors.bgHairline, width: 1.5),
                      ),
                      child: Icon(AppIcons.moon, size: AppTheme.iconXl, color: band.connected ? AppColors.gold : AppColors.textMuted),
                    ),
                    const SizedBox(height: AppTheme.spaceL),
                    Text('Umbra-4F21', style: AppTypography.titleL()),
                    const SizedBox(height: AppTheme.spaceS),
                    StatusChip(
                      label: band.connected ? 'Connected' : 'Offline',
                      icon: band.connected ? AppIcons.bluetooth : AppIcons.bluetoothOff,
                      color: band.connected ? AppColors.success : AppColors.textMuted,
                      tint: band.connected ? AppColors.successTint : AppColors.bgHairline,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spaceXxxl),
              Container(
                padding: const EdgeInsets.all(AppTheme.spaceL),
                decoration: BoxDecoration(color: AppColors.bgSurface, borderRadius: BorderRadius.circular(AppTheme.radiusM)),
                child: Row(
                  children: [
                    Expanded(child: LabeledStat(label: 'Battery', value: '${band.battery}%', valueStyle: AppTypography.titleM())),
                    Expanded(child: LabeledStat(label: 'Resting HR', value: '${band.restingHr} bpm', valueStyle: AppTypography.titleM())),
                    Expanded(child: LabeledStat(label: 'Firmware', value: '1.2.0', valueStyle: AppTypography.titleM())),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spaceL),
              Text(
                'Umbra works standalone even when the app is closed. Reminders keep firing on schedule whether the band is connected here or not.',
                style: AppTypography.bodyS(),
              ),
              const Spacer(),
              if (band.connected)
                AppButton(
                  label: 'Forget this band',
                  variant: AppButtonVariant.secondary,
                  onTap: () => _forget(context, band),
                )
              else
                AppButton(label: 'Reconnect', icon: AppIcons.bluetooth, onTap: () => _reconnect(context)),
              const SizedBox(height: AppTheme.spaceL),
            ],
          ),
        ),
      ),
    );
  }
}
