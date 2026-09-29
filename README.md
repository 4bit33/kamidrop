# KamiDrop

Легкий локальний друк на мережеві принтери: пошук через mDNS, друк через IPP
в AirPrint-растрі (`image/urf`). Без драйверів, акаунтів і хмари.

Зараз уміє:
- постійно шукати принтери в мережі (`_ipp._tcp`, `_ipps._tcp`) і пам'ятати знайдені;
- показувати можливості принтера: колір, дуплекс, роздільність, рівні чорнила/тонера;
- додавати принтер вручну за IP, якщо mDNS мовчить;
- друкувати PDF і зображення: превʼю, вибір сторінок, альбомні сторінки повертаються автоматично;
- мініредактор макета з живим превʼю аркуша: орієнтація, «вписати» / «заповнити» / 100 % / свій масштаб, розміри фото 9×13, 10×15, 13×18, A5 з кадруванням, поля, розташування;
- друкувати вбудовану тестову сторінку (колір, двосторонній друк, копії).

## Запуск на Linux

Потрібні Flutter SDK і інструменти для десктопу:

```
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
```

У теці проєкту згенеруй платформні файли (наші файли не перезапишуться):

```
flutter create . --org dev.fourbit --project-name kamidrop --platforms=linux,android,windows
flutter pub get
flutter test
flutter run -d linux
```

## Структура

```
lib/
  main.dart                  застосунок і запуск пошуку
  theme.dart                 палітра (васі, сумі, шу)
  ipp/ipp.dart               кодування запитів і розбір відповідей IPP
  ipp/ipp_client.dart        HTTP-транспорт, Get-Printer-Attributes, Print-Job, Get-Job-Attributes
  discovery/discovery.dart   фоновий пошук (Android — NsdManager, інші — mDNS), пам'ять принтерів, ручне додавання
  printing/capabilities.dart що вміє принтер (URF, dpi, дуплекс, маркери)
  printing/urf.dart          кодувальник/декодувальник URF, перевертання зворотного боку
  printing/sources.dart      джерела друку: PDF (pdfrx), зображення, тестова сторінка
  printing/compose.dart      вписування в A4, поворот, сірий/sRGB, діапазони сторінок
  printing/test_page.dart    тестова сторінка через dart:ui
  printing/print_service.dart конвеєр друку: рендер → URF (в ізоляті) → Print-Job → статус
  ui/                        список принтерів, аркуш друку, редактор макета
test/                        тести IPP, URF і головного екрана
```

## Android

- `android/app/src/main/AndroidManifest.xml` — дозволи на мережу й multicast, пункти «Поділитися» та «Відкрити за допомогою».
- `android/app/src/main/kotlin/dev/fourbit/kamidrop/MainActivity.kt` — системний пошук принтерів (NsdManager), multicast lock і прийом файлів.
- `lib/platform/platform_bridge.dart` — Dart-бік цього мосту.

Запуск на телефоні: увімкнути «Налагодження через USB», під'єднати кабелем, `flutter run`.
