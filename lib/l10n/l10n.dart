// Доступ до перекладів звідусіль, зокрема з коду без BuildContext (друк, сканер, IPP).
// Поточну мову задає корінь застосунку (main.dart); типово — українська (зручно й для тестів).
import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

L10n _current = lookupL10n(const Locale('uk'));

L10n get l10n => _current;

void setL10n(L10n value) => _current = value;

/// Дробове число з комою по-українськи й крапкою по-англійськи.
String decimal(double v, int digits) {
  final s = v.toStringAsFixed(digits);
  return _current.localeName.startsWith('uk') ? s.replaceAll('.', ',') : s;
}

/// Вибрана мова: 'system' (за системою), 'uk' або 'en'. Корінь застосунку слухає й перебудовується.
final appLanguage = ValueNotifier<String>('system');

/// Мова для системної локалі: українська для «uk», англійська — для решти.
Locale resolveAppLocale(Locale? system) =>
    system?.languageCode == 'uk' ? const Locale('uk') : const Locale('en');
