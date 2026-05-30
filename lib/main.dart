import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_i18n.dart';
import 'screens/landing_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } catch (_) {}

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatefulWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AppLanguageController _language = AppLanguageController();

  @override
  Widget build(BuildContext context) {
    return AppLanguageScope(
      controller: _language,
      child: ValueListenableBuilder<AppLanguage>(
        valueListenable: _language,
        builder: (context, lang, _) {
          // Keep [MaterialApp.locale] as English. Flutter has no
          // [MaterialLocalizations] for Waray/Tagalog; our UI strings use [AppI18n]
          // from [AppLanguageScope] instead.
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en')],
            locale: const Locale('en'),
            home: LandingScreen(cameras: widget.cameras),
          );
        },
      ),
    );
  }
}
