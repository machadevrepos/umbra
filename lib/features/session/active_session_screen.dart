import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_theme.dart';
import '../../core/constants/app_typography.dart';
import '../../core/state/band_controller.dart';
import '../../core/state/session_controller.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/labeled_stat.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/widgets/status_chip.dart';
import 'widgets/end_session_sheet.dart';

class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key});
  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  late final SessionController _session;
  bool _ending = false;
  bool _seenActive = false;
  @override
  void initState() {
    super.initState();
    _session = context.read<SessionController>();
    _seenActive = _session.isActive;
    _session.addListener(_changed);
  }

  void _changed() {
    if (_seenActive && !_session.isActive && !_ending && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
          Navigator.of(context).pop();
        }
      });
    }
    _seenActive = _session.isActive;
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    super.dispose();
  }

  String _elapsed(int seconds) => seconds >= 3600
      ? '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m'
      : '${seconds ~/ 60}m ${seconds % 60}s';
  Future<void> _end() async {
    if (!await showEndSessionSheet(
          context,
          elapsedLabel: _elapsed(_session.elapsedSeconds),
        ) ||
        !mounted) {
      return;
    }
    setState(() => _ending = true);
    try {
      await _session.endSession();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reconnect your band to end Night Mode.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final band = context.watch<BandController>();
    final hr = session.hr;
    final zone = hr == null
        ? 'No heart rate reading'
        : hr < 90
        ? 'Resting'
        : hr < 116
        ? 'Elevated'
        : 'High';
    final color = hr == null
        ? AppColors.textSecondary
        : hr < 90
        ? AppColors.success
        : hr < 116
        ? AppColors.gold
        : AppColors.error;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.screenPaddingH),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PressableScale(
                onTap: () => Navigator.of(context).pop(),
                semanticLabel: 'Back to Home, band keeps running',
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
            const SizedBox(height: AppTheme.spaceXxl),
            Text(
              'Night session',
              style: AppTypography.titleL(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spaceXxxl),
            Center(
              child: Container(
                width: 232,
                height: 232,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bgHairline),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hr?.toString() ?? '\u2014',
                      style: AppTypography.displayL(color: AppColors.gold),
                    ),
                    Text('BPM', style: AppTypography.labelS()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceXl),
            Center(
              child: StatusChip(
                label: zone,
                icon: hr == null ? AppIcons.bluetooth : AppIcons.heart,
                color: color,
                tint: AppColors.bgHairline,
              ),
            ),
            const SizedBox(height: AppTheme.spaceL),
            Text(
              session.hardwareConfirmed
                  ? 'Your band manages reminders every ${band.nightIntervalMinutes} min.'
                  : 'Connection lost. Your band keeps running independently.',
              style: AppTypography.bodyM(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spaceS),
            Text(
              '${_elapsed(session.elapsedSeconds)} tracked',
              style: AppTypography.bodyS(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spaceXxxl),
            LabeledStat(
              label: 'Latest SpO2',
              value: session.spo2 == null
                  ? 'No recent reading'
                  : '${session.spo2}%',
            ),
            const SizedBox(height: AppTheme.spaceS),
            Text(
              band.spo2Reading?.statusLabel ??
                  'Measured by your band during spot checks.',
              style: AppTypography.bodyS(),
            ),
            const SizedBox(height: AppTheme.spaceL),
            LabeledStat(
              label: 'Session steps',
              value: session.hardwareConfirmed && session.steps != null
                  ? '${session.steps}'
                  : 'Available after band sync',
            ),
            const SizedBox(height: AppTheme.spaceXxxl),
            AppButton(
              label: _ending ? 'Ending on your band' : 'End session',
              variant: AppButtonVariant.secondary,
              onTap: band.canControl && !_ending ? _end : null,
            ),
          ],
        ),
      ),
    );
  }
}
