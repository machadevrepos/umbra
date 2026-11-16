import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/morning_checkin_controller.dart';
import '../../core/state/session_store.dart';
import '../checkin/morning_checkin_screen.dart';
import '../../core/constants/app_colors.dart';
import '../history/history_screen.dart';
import '../home/home_screen.dart';
import '../insights/insights_screen.dart';
import '../settings/settings_screen.dart';
import 'widgets/umbra_bottom_nav.dart';

/// Owns the bottom nav and swaps tab bodies via `IndexedStack` so each tab
/// keeps its scroll position and state when you switch away and back,
/// rather than every tab screen carrying its own `Scaffold` and rebuilding
/// from scratch. Home, History, Insights, Settings are content only; this
/// is the one place the tab chrome lives.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late final MorningCheckinController _checkins;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _checkins = context.read<MorningCheckinController>();
    _checkins.addListener(_checkNotification);
    _checkNotification();
  }

  void _checkNotification() {
    if (_checkins.pendingSessionId == null || _opening) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openNotification());
  }

  Future<void> _openNotification() async {
    if (!mounted || _opening) return;
    final id = _checkins.takePendingSession();
    if (id == null) return;
    _opening = true;
    final store = context.read<SessionStore>();
    await store.ready;
    if (!mounted) return;
    final sessions = store.history.where(
      (s) => s.id == id && s.checkInRating == null,
    );
    if (sessions.isNotEmpty) {
      final session = sessions.first;
      final rating = await Navigator.of(context).push<int>(
        MaterialPageRoute(
          builder: (_) => MorningCheckinScreen(
            sessionSummary: 'Night session, ${session.durationLabel}',
          ),
        ),
      );
      if (rating != null) await store.attachCheckIn(id, rating);
    }
    _opening = false;
    if (mounted) _checkNotification();
  }

  @override
  void dispose() {
    _checkins.removeListener(_checkNotification);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgVoid,
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          HistoryScreen(),
          InsightsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: UmbraBottomNav(
        activeIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
