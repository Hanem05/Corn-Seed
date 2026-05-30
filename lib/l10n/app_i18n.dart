import 'package:flutter/widgets.dart';

enum AppLanguage { english, waray, tagalog }

class AppLanguageController extends ValueNotifier<AppLanguage> {
  AppLanguageController() : super(AppLanguage.english);
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguageController controllerOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    assert(scope != null, 'AppLanguageScope not found in widget tree.');
    return scope!.notifier!;
  }
}

class AppI18n {
  static AppLanguage _lang(BuildContext context) =>
      AppLanguageScope.controllerOf(context).value;

  static String t(BuildContext context, String key) {
    final lang = _lang(context);
    return _localized[key]?[lang] ?? _localized[key]?[AppLanguage.english] ?? key;
  }

  /// Replaces `{{mode}}` with [modeLabel] (e.g. Variety / Viability in the active language).
  static String tMode(BuildContext context, String key, String modeLabel) {
    return t(context, key).replaceAll('{{mode}}', modeLabel);
  }

  static const Map<String, Map<AppLanguage, String>> _localized = {
    'app.title': {
      AppLanguage.english: 'Corn seed detector',
      AppLanguage.waray: 'Detektor han liso han mais',
      AppLanguage.tagalog: 'Detektor ng buto ng mais',
    },
    'landing.subtitle': {
      AppLanguage.english: 'YOLO finds seeds, then pick what to run on each crop.',
      AppLanguage.waray:
          'An YOLO nakakakita han mga liso, tapos pili-a kon ano nga modelo an ipadagan kada crop.',
      AppLanguage.tagalog:
          'Hinahanap ng YOLO ang mga buto, tapos piliin kung anong model ang tatakbo sa bawat crop.',
    },
    'landing.scan_mode': {
      AppLanguage.english: 'Scan mode',
      AppLanguage.waray: 'Pamaagi han pag-scan',
      AppLanguage.tagalog: 'Mode ng pag-scan',
    },
    'landing.language': {
      AppLanguage.english: 'Language',
      AppLanguage.waray: 'Pinulongan',
      AppLanguage.tagalog: 'Wika',
    },
    'mode.variety': {
      AppLanguage.english: 'Variety',
      AppLanguage.waray: 'Variety',
      AppLanguage.tagalog: 'Variety',
    },
    'mode.viability': {
      AppLanguage.english: 'Viability',
      AppLanguage.waray: 'Viability',
      AppLanguage.tagalog: 'Viability',
    },
    'landing.realtime': {
      AppLanguage.english: 'Real-time',
      AppLanguage.waray: 'Real-time',
      AppLanguage.tagalog: 'Real-time',
    },
    'landing.capture': {
      AppLanguage.english: 'Capture seeds',
      AppLanguage.waray: 'Kuhaa an liso',
      AppLanguage.tagalog: 'Kunan ang mga buto',
    },
    'landing.no_camera': {
      AppLanguage.english: 'No camera found on this device.',
      AppLanguage.waray: 'Waray camera nga nakita hini nga device.',
      AppLanguage.tagalog: 'Walang nakitang camera sa device na ito.',
    },
    'lang.english': {
      AppLanguage.english: 'English',
      AppLanguage.waray: 'English',
      AppLanguage.tagalog: 'Ingles',
    },
    'lang.waray': {
      AppLanguage.english: 'Waray-Waray (PH)',
      AppLanguage.waray: 'Waray-Waray (PH)',
      AppLanguage.tagalog: 'Waray-Waray (PH)',
    },
    'lang.tagalog': {
      AppLanguage.english: 'Tagalog (PH)',
      AppLanguage.waray: 'Tagalog (PH)',
      AppLanguage.tagalog: 'Tagalog (PH)',
    },
    'guide.title': {
      AppLanguage.english: 'Before you scan',
      AppLanguage.waray: 'Antes ka mag-scan',
      AppLanguage.tagalog: 'Bago mag-scan',
    },
    'guide.realtime_headline': {
      AppLanguage.english: 'Real-time scan',
      AppLanguage.waray: 'Real-time nga pag-scan',
      AppLanguage.tagalog: 'Real-time na pag-scan',
    },
    'guide.capture_headline': {
      AppLanguage.english: 'Photo capture',
      AppLanguage.waray: 'Pagkuha hin retrato',
      AppLanguage.tagalog: 'Pagkuha ng larawan',
    },
    'guide.continue_live': {
      AppLanguage.english: 'Continue to live scan',
      AppLanguage.waray: 'Padayon ngadto ha live scan',
      AppLanguage.tagalog: 'Magpatuloy sa live scan',
    },
    'guide.continue_camera': {
      AppLanguage.english: 'Continue to camera',
      AppLanguage.waray: 'Padayon ngadto ha camera',
      AppLanguage.tagalog: 'Magpatuloy sa camera',
    },
    'guide.subtitle_realtime': {
      AppLanguage.english:
          'Live camera: detections refresh on a short interval. {{mode}} runs on each seed crop.',
      AppLanguage.waray:
          'Live camera: nagbag-o an mga deteksyon ha diri-diri nga oras. An {{mode}} nagadalagan ha tagsa nga crop han liso.',
      AppLanguage.tagalog:
          'Live camera: pana-panahong nagre-refresh ang mga detection. Ang {{mode}} ay tumatakbo sa bawat crop ng buto.',
    },
    'guide.subtitle_capture': {
      AppLanguage.english:
          'Take one still photo; results appear after processing. {{mode}} runs on each detected seed.',
      AppLanguage.waray:
          'Kuhaa usa nga still nga retrato; makita an resulta human maproseso. An {{mode}} nagadalagan ha tagsa nga liso nga nakita.',
      AppLanguage.tagalog:
          'Kumuha ng isang still na larawan; lalabas ang resulta pagkatapos iproseso. Ang {{mode}} ay tumatakbo sa bawat natukoy na buto.',
    },
    'guide.bullet_lighting': {
      AppLanguage.english:
          'Use bright, even lighting. Harsh shadows or backlight can hurt detection and classification.',
      AppLanguage.waray:
          'Gamita masanag nga suga nga patas. An hait nga landong o suga tikang likod makasamad ha deteksyon ug klasipikasyon.',
      AppLanguage.tagalog:
          'Gumamit ng maliwanag at pantay na ilaw. Ang matinding anino o backlight ay makakasama sa detection at klasipikasyon.',
    },
    'guide.bullet_focus': {
      AppLanguage.english:
          'Keep seeds in focus and fill the frame—move closer so kernels are clearly visible.',
      AppLanguage.waray:
          'Bantayi nga naka-focus an mga liso ug pun-a an frame—duol kadi para maklaro an mga liso.',
      AppLanguage.tagalog:
          'Panatilihing naka-focus ang mga buto at punuin ang frame—lumapit para malinaw ang mga butil.',
    },
    'guide.bullet_realtime_timer': {
      AppLanguage.english:
          'Wait a moment between updates; the app analyzes frames on a timer, not every frame.',
      AppLanguage.waray:
          'Hulag kadi gamay; an app naganalisa hin mga frame sunod timer, diri tagsa nga frame.',
      AppLanguage.tagalog:
          'Maghintay sandali sa pagitan ng update; ang app ay nag-aanalyze ng mga frame ayon sa timer, hindi bawat frame.',
    },
    'guide.bullet_capture_steady': {
      AppLanguage.english:
          'Hold steady when you tap Capture. Review the result screen, then use Capture again for a new shot.',
      AppLanguage.waray:
          'Hupti nga kalmado kon mag-tap Capture. Tan-awa an resulta, tapos Capture utro para bag-o nga kuha.',
      AppLanguage.tagalog:
          'Panatilihing nakatayo nang matatag kapag nag-tap ng Capture. Tingnan ang resulta, pagkatapos gamitin muli ang Capture para sa bagong kuha.',
    },
    'guide.bullet_variety_color': {
      AppLanguage.english:
          'For variety, natural color and texture matter. Avoid heavy filters or tinted glass over the lens.',
      AppLanguage.waray:
          'Para ha variety, importante an natural nga kolor ug tekstura. Likayi an grabe nga filter o may kolor nga salamin sa lens.',
      AppLanguage.tagalog:
          'Para sa variety, mahalaga ang natural na kulay at texture. Iwasan ang mabibigat na filter o may kulay na salamin sa lens.',
    },
    'guide.bullet_viability_surface': {
      AppLanguage.english:
          'For viability, aim for a clear view of the seed surface so the model can judge condition.',
      AppLanguage.waray:
          'Para ha viability, klaro nga tan-awon an ibabaw han liso agud makahukom an modelo.',
      AppLanguage.tagalog:
          'Para sa viability, siguruhing malinaw ang ibabaw ng buto para mahusay hatulan ng modelo.',
    },
    'guide.bullet_disclaimer': {
      AppLanguage.english:
          'On-screen percentages are aids for screening only—not a substitute for lab testing when decisions are critical.',
      AppLanguage.waray:
          'An mga porsyento ha screen para la screening la—diri kapilian sa laboratoryo kon kritikal an desisyon.',
      AppLanguage.tagalog:
          'Ang mga porsyento sa screen ay pantulong sa screening lamang—hindi kapalit ng lab test kung kritikal ang desisyon.',
    },
  };
}
