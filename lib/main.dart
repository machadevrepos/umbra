import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/state/band_controller.dart';
import 'core/state/session_controller.dart';
import 'core/state/session_store.dart';
import 'core/state/settings_controller.dart';
import 'core/state/morning_checkin_controller.dart';
import 'core/theme/app_theme_data.dart';
import 'features/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(umbraSystemUiOverlayStyle);
  runApp(const UmbraApp());
}

class UmbraApp extends StatelessWidget {
  const UmbraApp({super.key, this.sessionStore, this.bandController});

  final SessionStore? sessionStore;
  final BandController? bandController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => sessionStore ?? SessionStore()),
        ChangeNotifierProvider(
          create: (context) =>
              bandController ??
              BandController(history: context.read<SessionStore>()),
        ),
        ChangeNotifierProvider(create: (_) => SettingsController()),
        ChangeNotifierProvider(
          create: (context) => SessionController(
            band: context.read<BandController>(),
            history: context.read<SessionStore>(),
          ),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (context) => MorningCheckinController(
            store: context.read<SessionStore>(),
            settings: context.read<SettingsController>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Umbra',
        debugShowCheckedModeBanner: false,
        theme: buildUmbraTheme(),
        home: const SplashScreen(),
      ),
    );
  }
}
