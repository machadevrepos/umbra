import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra/core/constants/app_icons.dart';
import 'package:umbra/core/state/band_controller.dart';
import 'package:umbra/core/state/session_store.dart';
import 'package:umbra/main.dart';

Future<void> advance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android runs without fake readings, fake history or an offline session start',
    (tester) async {
      await (await SharedPreferences.getInstance()).clear();
      await tester.pumpWidget(const UmbraApp());
      await advance(tester);
      await tester.pump(const Duration(seconds: 2));
      await advance(tester);
      await tester.tap(find.text('Skip'));
      await advance(tester);
      await tester.tap(find.text('Maybe later'));
      await advance(tester);
      await tester.tap(find.text('Skip for now'));
      await advance(tester);
      final context = tester.element(find.byType(MaterialApp));
      expect(context.read<BandController>().connected, isFalse);
      expect(context.read<SessionStore>().history, isEmpty);
      expect(find.text('Connect your band'), findsOneWidget);
      expect(find.text('Start session'), findsNothing);
      await tester.tap(find.text('Night'));
      await advance(tester);
      expect(find.text('Session in progress'), findsNothing);
      await tester.tap(find.byIcon(AppIcons.history));
      await advance(tester);
      expect(find.text('Night session'), findsNothing);
      await tester.tap(find.byIcon(AppIcons.settings));
      await advance(tester);
      expect(find.text('Manage band'), findsOneWidget);
      await tester.tap(find.text('Manage band'));
      await advance(tester);
      expect(find.text('No reading'), findsOneWidget);
      expect(context.read<BandController>().canControl, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
