import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_theme.dart';
import '../../core/constants/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/widgets/pulse_radar.dart';
import '../shell/main_shell.dart';

enum _PairingStage { scanning, found, connecting, connected }

/// Mock BLE flow for design review: scanning/found/connecting/connected
/// timings are simulated with `Timer`s. Swaps to the real `flutter_reactive_ble`
/// (or equivalent) scan/connect stream once the BLE integration layer
/// exists; the state machine and its visuals shouldn't need to change
/// shape, just where the state transitions come from.
class BandPairingScreen extends StatefulWidget {
  const BandPairingScreen({super.key});

  @override
  State<BandPairingScreen> createState() => _BandPairingScreenState();
}

class _BandPairingScreenState extends State<BandPairingScreen> {
  _PairingStage _stage = _PairingStage.scanning;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _stage = _PairingStage.found);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _connect() {
    setState(() => _stage = _PairingStage.connecting);
    _timer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _stage = _PairingStage.connected);
      _timer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) _goHome();
      });
    });
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
  }

  @override
  Widget build(BuildContext context) {
    final connected = _stage == _PairingStage.connected;

    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPaddingH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppTheme.spaceXxl),
              Text('Find your band', style: AppTypography.titleL()),
              const SizedBox(height: AppTheme.spaceS),
              Text(
                "Make sure it's charged and nearby. You can skip this. Umbra works standalone.",
                style: AppTypography.bodyM(),
              ),
              const Spacer(),
              Center(
                child: AnimatedSwitcher(
                  duration: AppTheme.animNormal,
                  child: connected
                      ? _ConnectedMark(key: const ValueKey('connected'))
                      : PulseRadar(
                          key: const ValueKey('radar'),
                          child: const Icon(AppIcons.bluetooth, size: AppTheme.iconL, color: AppColors.gold),
                        ),
                ),
              ),
              const SizedBox(height: AppTheme.spaceXxl),
              Center(child: _StageLabel(stage: _stage)),
              const SizedBox(height: AppTheme.spaceXl),
              AnimatedSwitcher(
                duration: AppTheme.animFast,
                child: _stage == _PairingStage.found || _stage == _PairingStage.connecting
                    ? const _DeviceCard(key: ValueKey('device'))
                    : const SizedBox(key: ValueKey('empty'), height: 0),
              ),
              const Spacer(),
              if (!connected) ...[
                AppButton(
                  label: _stage == _PairingStage.connecting ? 'Connecting' : 'Connect',
                  onTap: _stage == _PairingStage.found ? _connect : null,
                  loading: _stage == _PairingStage.connecting,
                ),
                const SizedBox(height: AppTheme.spaceM),
                Center(
                  child: PressableScale(
                    onTap: _goHome,
                    semanticLabel: 'Skip for now',
                    child: Container(
                      height: AppTheme.minTapTarget,
                      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceM),
                      alignment: Alignment.center,
                      child: Text('Skip for now', style: AppTypography.labelL(color: AppColors.textMuted)),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spaceM),
              ] else
                const SizedBox(height: AppTheme.minTapTarget + 8 + AppTheme.spaceM + AppTheme.minTapTarget + AppTheme.spaceM),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageLabel extends StatelessWidget {
  const _StageLabel({required this.stage});
  final _PairingStage stage;

  @override
  Widget build(BuildContext context) {
    final text = switch (stage) {
      _PairingStage.scanning => 'Scanning for nearby bands…',
      _PairingStage.found => 'Band found',
      _PairingStage.connecting => 'Connecting…',
      _PairingStage.connected => 'Connected',
    };
    return AnimatedSwitcher(
      duration: AppTheme.animFast,
      child: Text(text, key: ValueKey(text), style: AppTypography.bodyL(color: AppColors.textSecondary)),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spaceL),
      decoration: BoxDecoration(color: AppColors.bgSurface, borderRadius: BorderRadius.circular(AppTheme.radiusM)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.bgHairline, shape: BoxShape.circle),
            child: const Icon(AppIcons.moon, size: AppTheme.iconM, color: AppColors.gold),
          ),
          const SizedBox(width: AppTheme.spaceL),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Umbra-4F21', style: AppTypography.titleS()),
              const SizedBox(height: 2),
              Text('Nearby · Strong signal', style: AppTypography.bodyS()),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectedMark extends StatelessWidget {
  const _ConnectedMark({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1.0),
      duration: reduceMotion ? Duration.zero : AppTheme.animNormal,
      curve: AppTheme.motionCurve,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        width: 88,
        height: 88,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.successTint, shape: BoxShape.circle, border: Border.all(color: AppColors.success, width: 1.5)),
        child: const Icon(AppIcons.check, size: AppTheme.iconXl, color: AppColors.success),
      ),
    );
  }
}
