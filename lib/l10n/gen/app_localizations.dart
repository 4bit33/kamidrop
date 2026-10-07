import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('uk')
  ];

  /// No description provided for @appTitle.
  ///
  /// In uk, this message translates to:
  /// **'KamiDrop'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In uk, this message translates to:
  /// **'Скасувати'**
  String get cancel;

  /// No description provided for @cancelling.
  ///
  /// In uk, this message translates to:
  /// **'Скасовую…'**
  String get cancelling;

  /// No description provided for @done.
  ///
  /// In uk, this message translates to:
  /// **'Готово'**
  String get done;

  /// No description provided for @add.
  ///
  /// In uk, this message translates to:
  /// **'Додати'**
  String get add;

  /// No description provided for @remove.
  ///
  /// In uk, this message translates to:
  /// **'Прибрати'**
  String get remove;

  /// No description provided for @tryAgain.
  ///
  /// In uk, this message translates to:
  /// **'Спробувати ще раз'**
  String get tryAgain;

  /// No description provided for @settings.
  ///
  /// In uk, this message translates to:
  /// **'Налаштування'**
  String get settings;

  /// No description provided for @color.
  ///
  /// In uk, this message translates to:
  /// **'Колір'**
  String get color;

  /// No description provided for @duplex.
  ///
  /// In uk, this message translates to:
  /// **'Двосторонній'**
  String get duplex;

  /// No description provided for @blackWhiteShort.
  ///
  /// In uk, this message translates to:
  /// **'Ч/Б'**
  String get blackWhiteShort;

  /// No description provided for @scan.
  ///
  /// In uk, this message translates to:
  /// **'Сканувати'**
  String get scan;

  /// No description provided for @share.
  ///
  /// In uk, this message translates to:
  /// **'Поділитися'**
  String get share;

  /// No description provided for @save.
  ///
  /// In uk, this message translates to:
  /// **'Зберегти'**
  String get save;

  /// No description provided for @printShort.
  ///
  /// In uk, this message translates to:
  /// **'Друк'**
  String get printShort;

  /// No description provided for @error.
  ///
  /// In uk, this message translates to:
  /// **'Помилка'**
  String get error;

  /// No description provided for @no.
  ///
  /// In uk, this message translates to:
  /// **'Ні'**
  String get no;

  /// No description provided for @turnOn.
  ///
  /// In uk, this message translates to:
  /// **'Увімкнути'**
  String get turnOn;

  /// No description provided for @later.
  ///
  /// In uk, this message translates to:
  /// **'Пізніше'**
  String get later;

  /// No description provided for @update.
  ///
  /// In uk, this message translates to:
  /// **'Оновити'**
  String get update;

  /// No description provided for @check.
  ///
  /// In uk, this message translates to:
  /// **'Перевірити'**
  String get check;

  /// No description provided for @checking.
  ///
  /// In uk, this message translates to:
  /// **'Перевіряю…'**
  String get checking;

  /// No description provided for @mm.
  ///
  /// In uk, this message translates to:
  /// **'{n} мм'**
  String mm(int n);

  /// No description provided for @sizeCm.
  ///
  /// In uk, this message translates to:
  /// **'{w} × {h} см'**
  String sizeCm(String w, String h);

  /// No description provided for @printersNearby.
  ///
  /// In uk, this message translates to:
  /// **'Принтери поруч'**
  String get printersNearby;

  /// No description provided for @searchingNearby.
  ///
  /// In uk, this message translates to:
  /// **'Шукаю принтери поруч…'**
  String get searchingNearby;

  /// No description provided for @searchAgain.
  ///
  /// In uk, this message translates to:
  /// **'Шукати знову'**
  String get searchAgain;

  /// No description provided for @searchingPrinters.
  ///
  /// In uk, this message translates to:
  /// **'Шукаю принтери…'**
  String get searchingPrinters;

  /// No description provided for @noPrintersYet.
  ///
  /// In uk, this message translates to:
  /// **'Принтерів поки не видно'**
  String get noPrintersYet;

  /// No description provided for @noPrintersHint.
  ///
  /// In uk, this message translates to:
  /// **'Переконайся, що принтер увімкнений і в тій самій Wi-Fi мережі.\nПотягни список донизу, щоб шукати знову.'**
  String get noPrintersHint;

  /// No description provided for @addPrinterByIp.
  ///
  /// In uk, this message translates to:
  /// **'Додати принтер за IP-адресою'**
  String get addPrinterByIp;

  /// No description provided for @printerByIp.
  ///
  /// In uk, this message translates to:
  /// **'Принтер за IP'**
  String get printerByIp;

  /// No description provided for @pickPrinterBelow.
  ///
  /// In uk, this message translates to:
  /// **'Вибери принтер нижче'**
  String get pickPrinterBelow;

  /// No description provided for @removeFile.
  ///
  /// In uk, this message translates to:
  /// **'Прибрати файл'**
  String get removeFile;

  /// No description provided for @lastUsed.
  ///
  /// In uk, this message translates to:
  /// **'останній'**
  String get lastUsed;

  /// No description provided for @justPoweredOn.
  ///
  /// In uk, this message translates to:
  /// **'Щойно ввімкнувся — може ще прогріватися'**
  String get justPoweredOn;

  /// No description provided for @scannerAt.
  ///
  /// In uk, this message translates to:
  /// **'Сканер · {host}'**
  String scannerAt(String host);

  /// No description provided for @searchFailed.
  ///
  /// In uk, this message translates to:
  /// **'Пошук у мережі не вдався: {error}'**
  String searchFailed(String error);

  /// No description provided for @unknownPrinter.
  ///
  /// In uk, this message translates to:
  /// **'Невідомий принтер'**
  String get unknownPrinter;

  /// No description provided for @updateAvailable.
  ///
  /// In uk, this message translates to:
  /// **'Є нова версія {version}'**
  String updateAvailable(String version);

  /// No description provided for @updateDownloading.
  ///
  /// In uk, this message translates to:
  /// **'Завантажую версію {version}… {percent} %'**
  String updateDownloading(String version, int percent);

  /// No description provided for @updateInstalling.
  ///
  /// In uk, this message translates to:
  /// **'Встановлюю версію {version}…'**
  String updateInstalling(String version);

  /// No description provided for @updateInstallFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося встановити: {error}'**
  String updateInstallFailed(String error);

  /// No description provided for @updateCheckFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося перевірити оновлення: {error}'**
  String updateCheckFailed(String error);

  /// No description provided for @updateDownloadFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося завантажити оновлення: {error}'**
  String updateDownloadFailed(String error);

  /// No description provided for @updateAllowInstall.
  ///
  /// In uk, this message translates to:
  /// **'Дозволь KamiDrop встановлювати застосунки й натисни «Оновити» ще раз'**
  String get updateAllowInstall;

  /// No description provided for @autoOpenTitle.
  ///
  /// In uk, this message translates to:
  /// **'Одразу відкривати друк'**
  String get autoOpenTitle;

  /// No description provided for @autoOpenSubtitle.
  ///
  /// In uk, this message translates to:
  /// **'Файл із «Поділитися» відкривається на останньому принтері (або на єдиному, якщо він один)'**
  String get autoOpenSubtitle;

  /// No description provided for @lastFirstTitle.
  ///
  /// In uk, this message translates to:
  /// **'Останній принтер першим'**
  String get lastFirstTitle;

  /// No description provided for @lastFirstSubtitle.
  ///
  /// In uk, this message translates to:
  /// **'Ставити принтер, на якому друкував востаннє, на початок списку'**
  String get lastFirstSubtitle;

  /// No description provided for @rememberLayoutTitle.
  ///
  /// In uk, this message translates to:
  /// **'Пам\'ятати макет'**
  String get rememberLayoutTitle;

  /// No description provided for @rememberLayoutSubtitle.
  ///
  /// In uk, this message translates to:
  /// **'Фото й документи відкриваються з макетом минулого друку, а не з типовим'**
  String get rememberLayoutSubtitle;

  /// No description provided for @checkUpdatesTitle.
  ///
  /// In uk, this message translates to:
  /// **'Перевіряти оновлення'**
  String get checkUpdatesTitle;

  /// No description provided for @checkUpdatesSubtitle.
  ///
  /// In uk, this message translates to:
  /// **'Раз на добу дивитися, чи є нова версія KamiDrop. Встановлення — лише після твого натискання'**
  String get checkUpdatesSubtitle;

  /// No description provided for @upToDate.
  ///
  /// In uk, this message translates to:
  /// **'Встановлено найновішу версію'**
  String get upToDate;

  /// No description provided for @updateOnMainScreen.
  ///
  /// In uk, this message translates to:
  /// **'Є версія {version} — оновити можна на головному екрані'**
  String updateOnMainScreen(String version);

  /// No description provided for @versionLabel.
  ///
  /// In uk, this message translates to:
  /// **'Версія {version}'**
  String versionLabel(String version);

  /// No description provided for @language.
  ///
  /// In uk, this message translates to:
  /// **'Мова'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In uk, this message translates to:
  /// **'Як у системі'**
  String get languageSystem;

  /// No description provided for @gallery.
  ///
  /// In uk, this message translates to:
  /// **'Галерея'**
  String get gallery;

  /// No description provided for @galleryHint.
  ///
  /// In uk, this message translates to:
  /// **'Фото й зображення'**
  String get galleryHint;

  /// No description provided for @files.
  ///
  /// In uk, this message translates to:
  /// **'Файли'**
  String get files;

  /// No description provided for @filesHint.
  ///
  /// In uk, this message translates to:
  /// **'PDF і зображення з провідника'**
  String get filesHint;

  /// No description provided for @galleryFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося взяти фото з галереї: {error}'**
  String galleryFailed(String error);

  /// No description provided for @pdfAndImages.
  ///
  /// In uk, this message translates to:
  /// **'PDF і зображення'**
  String get pdfAndImages;

  /// No description provided for @images.
  ///
  /// In uk, this message translates to:
  /// **'Зображення'**
  String get images;

  /// No description provided for @gettingCaps.
  ///
  /// In uk, this message translates to:
  /// **'Отримую можливості принтера…'**
  String get gettingCaps;

  /// No description provided for @capsUnknown.
  ///
  /// In uk, this message translates to:
  /// **'Можливості принтера невідомі'**
  String get capsUnknown;

  /// No description provided for @pagesLabel.
  ///
  /// In uk, this message translates to:
  /// **'Сторінки'**
  String get pagesLabel;

  /// No description provided for @pagesHint.
  ///
  /// In uk, this message translates to:
  /// **'усі {count}, або напр. 1-3, 5'**
  String pagesHint(int count);

  /// No description provided for @pagesError.
  ///
  /// In uk, this message translates to:
  /// **'Номери від 1 до {count}'**
  String pagesError(int count);

  /// No description provided for @onlyBw.
  ///
  /// In uk, this message translates to:
  /// **'Цей принтер друкує лише чорно-біле'**
  String get onlyBw;

  /// No description provided for @duplexPrint.
  ///
  /// In uk, this message translates to:
  /// **'Двосторонній друк'**
  String get duplexPrint;

  /// No description provided for @notSupported.
  ///
  /// In uk, this message translates to:
  /// **'Не підтримується'**
  String get notSupported;

  /// No description provided for @copies.
  ///
  /// In uk, this message translates to:
  /// **'Копії'**
  String get copies;

  /// No description provided for @pickFileFirst.
  ///
  /// In uk, this message translates to:
  /// **'Спершу вибери файл'**
  String get pickFileFirst;

  /// No description provided for @print.
  ///
  /// In uk, this message translates to:
  /// **'Друкувати'**
  String get print;

  /// No description provided for @printPages.
  ///
  /// In uk, this message translates to:
  /// **'{count, plural, one{Друкувати {count} сторінку} few{Друкувати {count} сторінки} many{Друкувати {count} сторінок} other{Друкувати {count} сторінки}}'**
  String printPages(int count);

  /// No description provided for @testPage.
  ///
  /// In uk, this message translates to:
  /// **'Тестова сторінка'**
  String get testPage;

  /// No description provided for @noUrfShort.
  ///
  /// In uk, this message translates to:
  /// **'Принтер не підтримує AirPrint-растр'**
  String get noUrfShort;

  /// No description provided for @opening.
  ///
  /// In uk, this message translates to:
  /// **'Відкриваю…'**
  String get opening;

  /// No description provided for @chooseFile.
  ///
  /// In uk, this message translates to:
  /// **'Вибрати файл'**
  String get chooseFile;

  /// No description provided for @pagesTapToChange.
  ///
  /// In uk, this message translates to:
  /// **'{count} стор. · натисни, щоб змінити'**
  String pagesTapToChange(int count);

  /// No description provided for @pdfOrImage.
  ///
  /// In uk, this message translates to:
  /// **'PDF або зображення'**
  String get pdfOrImage;

  /// No description provided for @layoutHint.
  ///
  /// In uk, this message translates to:
  /// **'Ти вже вдруге ставиш той самий макет. Запам\'ятовувати його, щоб наступного разу він був одразу? Це можна змінити в налаштуваннях.'**
  String get layoutHint;

  /// No description provided for @editSheets.
  ///
  /// In uk, this message translates to:
  /// **'Редагувати аркуші'**
  String get editSheets;

  /// No description provided for @unitPage.
  ///
  /// In uk, this message translates to:
  /// **'Сторінка'**
  String get unitPage;

  /// No description provided for @unitSheet.
  ///
  /// In uk, this message translates to:
  /// **'Аркуш'**
  String get unitSheet;

  /// No description provided for @pageOf.
  ///
  /// In uk, this message translates to:
  /// **'{unit} {index} з {total}'**
  String pageOf(String unit, int index, int total);

  /// No description provided for @pageOfSelected.
  ///
  /// In uk, this message translates to:
  /// **'{unit} {index} · {pos} з {count} вибраних'**
  String pageOfSelected(String unit, int index, int pos, int count);

  /// No description provided for @orientation.
  ///
  /// In uk, this message translates to:
  /// **'Орієнтація'**
  String get orientation;

  /// No description provided for @orientationAuto.
  ///
  /// In uk, this message translates to:
  /// **'Авто'**
  String get orientationAuto;

  /// No description provided for @portrait.
  ///
  /// In uk, this message translates to:
  /// **'Книжкова'**
  String get portrait;

  /// No description provided for @landscape.
  ///
  /// In uk, this message translates to:
  /// **'Альбомна'**
  String get landscape;

  /// No description provided for @size.
  ///
  /// In uk, this message translates to:
  /// **'Розмір'**
  String get size;

  /// No description provided for @fit.
  ///
  /// In uk, this message translates to:
  /// **'Вписати'**
  String get fit;

  /// No description provided for @fill.
  ///
  /// In uk, this message translates to:
  /// **'Заповнити'**
  String get fill;

  /// No description provided for @custom.
  ///
  /// In uk, this message translates to:
  /// **'Свій'**
  String get custom;

  /// No description provided for @margins.
  ///
  /// In uk, this message translates to:
  /// **'Поля'**
  String get margins;

  /// No description provided for @edgeToEdge.
  ///
  /// In uk, this message translates to:
  /// **'До краю'**
  String get edgeToEdge;

  /// No description provided for @minimal.
  ///
  /// In uk, this message translates to:
  /// **'Мінімальні'**
  String get minimal;

  /// No description provided for @placement.
  ///
  /// In uk, this message translates to:
  /// **'Розташування'**
  String get placement;

  /// No description provided for @centered.
  ///
  /// In uk, this message translates to:
  /// **'По центру'**
  String get centered;

  /// No description provided for @top.
  ///
  /// In uk, this message translates to:
  /// **'Вгорі'**
  String get top;

  /// No description provided for @preparing.
  ///
  /// In uk, this message translates to:
  /// **'Готуюсь…'**
  String get preparing;

  /// No description provided for @cancelledBeforeSend.
  ///
  /// In uk, this message translates to:
  /// **'Скасовано — на принтер нічого не надіслано'**
  String get cancelledBeforeSend;

  /// No description provided for @jobPending.
  ///
  /// In uk, this message translates to:
  /// **'У черзі принтера'**
  String get jobPending;

  /// No description provided for @jobHeld.
  ///
  /// In uk, this message translates to:
  /// **'Утримується принтером'**
  String get jobHeld;

  /// No description provided for @jobProcessing.
  ///
  /// In uk, this message translates to:
  /// **'Друкується…'**
  String get jobProcessing;

  /// No description provided for @jobStopped.
  ///
  /// In uk, this message translates to:
  /// **'Принтер зупинився'**
  String get jobStopped;

  /// No description provided for @jobCanceled.
  ///
  /// In uk, this message translates to:
  /// **'Скасовано'**
  String get jobCanceled;

  /// No description provided for @jobAborted.
  ///
  /// In uk, this message translates to:
  /// **'Перервано принтером'**
  String get jobAborted;

  /// No description provided for @jobState.
  ///
  /// In uk, this message translates to:
  /// **'Стан: {state}'**
  String jobState(String state);

  /// No description provided for @capsUnknownYet.
  ///
  /// In uk, this message translates to:
  /// **'Можливості принтера ще не відомі'**
  String get capsUnknownYet;

  /// No description provided for @noUrf.
  ///
  /// In uk, this message translates to:
  /// **'Принтер не приймає AirPrint-растр (image/urf)'**
  String get noUrf;

  /// No description provided for @noPagesSelected.
  ///
  /// In uk, this message translates to:
  /// **'Не вибрано жодної сторінки'**
  String get noPagesSelected;

  /// No description provided for @preparingPage.
  ///
  /// In uk, this message translates to:
  /// **'Готую сторінку {page} з {total}…'**
  String preparingPage(int page, int total);

  /// No description provided for @prepareError.
  ///
  /// In uk, this message translates to:
  /// **'Помилка підготовки: {error}'**
  String prepareError(String error);

  /// No description provided for @sendingMb.
  ///
  /// In uk, this message translates to:
  /// **'Надсилаю {size} МБ…'**
  String sendingMb(String size);

  /// No description provided for @printerRejected.
  ///
  /// In uk, this message translates to:
  /// **'Принтер відхилив завдання ({details})'**
  String printerRejected(String details);

  /// No description provided for @sent.
  ///
  /// In uk, this message translates to:
  /// **'Надіслано'**
  String get sent;

  /// No description provided for @rebootedDuringPrint.
  ///
  /// In uk, this message translates to:
  /// **'Принтер перезавантажився під час друку — завдання, найпевніше, втрачено'**
  String get rebootedDuringPrint;

  /// No description provided for @stoppedResponding.
  ///
  /// In uk, this message translates to:
  /// **'Принтер перестав відповідати — перевір, чи надрукувалось'**
  String get stoppedResponding;

  /// No description provided for @sentNoStatus.
  ///
  /// In uk, this message translates to:
  /// **'Надіслано (статус завдання недоступний)'**
  String get sentNoStatus;

  /// No description provided for @sentStillPrinting.
  ///
  /// In uk, this message translates to:
  /// **'Надіслано (принтер ще працює)'**
  String get sentStillPrinting;

  /// No description provided for @printerSilentWaiting.
  ///
  /// In uk, this message translates to:
  /// **'Принтер не відповідає, чекаю…'**
  String get printerSilentWaiting;

  /// No description provided for @jobCancelledMayPrint.
  ///
  /// In uk, this message translates to:
  /// **'Завдання скасовано. Аркуш, що вже друкувався, може вийти'**
  String get jobCancelledMayPrint;

  /// No description provided for @tooLateToCancel.
  ///
  /// In uk, this message translates to:
  /// **'Запізно — принтер уже завершив це завдання'**
  String get tooLateToCancel;

  /// No description provided for @printerDidNotCancel.
  ///
  /// In uk, this message translates to:
  /// **'Принтер не скасував завдання ({details})'**
  String printerDidNotCancel(String details);

  /// No description provided for @cancelFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося скасувати: {error}'**
  String cancelFailed(String error);

  /// No description provided for @printerNotResponding.
  ///
  /// In uk, this message translates to:
  /// **'Принтер не відповідає. Спробуй його перезавантажити.'**
  String get printerNotResponding;

  /// No description provided for @noConnectionPrinter.
  ///
  /// In uk, this message translates to:
  /// **'Немає з\'єднання з принтером: {error}'**
  String noConnectionPrinter(String error);

  /// No description provided for @printerDroppedConnection.
  ///
  /// In uk, this message translates to:
  /// **'Принтер розірвав з\'єднання: {error}'**
  String printerDroppedConnection(String error);

  /// No description provided for @printerErrorStatus.
  ///
  /// In uk, this message translates to:
  /// **'Принтер відповів помилкою {status}'**
  String printerErrorStatus(String status);

  /// No description provided for @unknownIppError.
  ///
  /// In uk, this message translates to:
  /// **'Невідома помилка IPP'**
  String get unknownIppError;

  /// No description provided for @formatNotSupported.
  ///
  /// In uk, this message translates to:
  /// **'Формат «.{ext}» поки не підтримується. Можна PDF або зображення.'**
  String formatNotSupported(String ext);

  /// No description provided for @pdfOpenFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося відкрити PDF: {error}'**
  String pdfOpenFailed(String error);

  /// No description provided for @pageRenderFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося відрендерити сторінку {page}'**
  String pageRenderFailed(int page);

  /// No description provided for @imageReadFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося прочитати зображення: {error}'**
  String imageReadFailed(String error);

  /// No description provided for @collageName.
  ///
  /// In uk, this message translates to:
  /// **'Аркуш із {count} фото'**
  String collageName(int count);

  /// No description provided for @photo.
  ///
  /// In uk, this message translates to:
  /// **'Фото'**
  String get photo;

  /// No description provided for @collageTitle.
  ///
  /// In uk, this message translates to:
  /// **'Аркуш із фото'**
  String get collageTitle;

  /// No description provided for @addPhotos.
  ///
  /// In uk, this message translates to:
  /// **'Додати фото'**
  String get addPhotos;

  /// No description provided for @firstSheet.
  ///
  /// In uk, this message translates to:
  /// **'Це перший аркуш'**
  String get firstSheet;

  /// No description provided for @photoOnSheet.
  ///
  /// In uk, this message translates to:
  /// **'Фото на аркуші {n}'**
  String photoOnSheet(int n);

  /// No description provided for @cropHint.
  ///
  /// In uk, this message translates to:
  /// **'Кадрування: тягни фото в рамці, двома пальцями — ближче'**
  String get cropHint;

  /// No description provided for @noCrop.
  ///
  /// In uk, this message translates to:
  /// **'Без обрізки'**
  String get noCrop;

  /// No description provided for @rotate.
  ///
  /// In uk, this message translates to:
  /// **'Повернути'**
  String get rotate;

  /// No description provided for @whole.
  ///
  /// In uk, this message translates to:
  /// **'Ціле'**
  String get whole;

  /// No description provided for @duplicate.
  ///
  /// In uk, this message translates to:
  /// **'Копія'**
  String get duplicate;

  /// No description provided for @collageHint.
  ///
  /// In uk, this message translates to:
  /// **'Подвійний тап — кадрувати · тримай фото й свайпни іншим пальцем — на інший аркуш'**
  String get collageHint;

  /// No description provided for @scannerDefaultName.
  ///
  /// In uk, this message translates to:
  /// **'Сканер'**
  String get scannerDefaultName;

  /// No description provided for @scannerNotResponding.
  ///
  /// In uk, this message translates to:
  /// **'Сканер не відповідає'**
  String get scannerNotResponding;

  /// No description provided for @noConnectionScanner.
  ///
  /// In uk, this message translates to:
  /// **'Немає з\'єднання зі сканером: {error}'**
  String noConnectionScanner(String error);

  /// No description provided for @scannerBusy.
  ///
  /// In uk, this message translates to:
  /// **'Сканер зайнятий — спробуй за хвилину'**
  String get scannerBusy;

  /// No description provided for @scannerUnsupportedSettings.
  ///
  /// In uk, this message translates to:
  /// **'Сканер не підтримує такі налаштування (або в подавачі нема паперу)'**
  String get scannerUnsupportedSettings;

  /// No description provided for @scannerRejected.
  ///
  /// In uk, this message translates to:
  /// **'Сканер відхилив завдання (HTTP {status})'**
  String scannerRejected(int status);

  /// No description provided for @scannerNoJobAddress.
  ///
  /// In uk, this message translates to:
  /// **'Сканер не повідомив адресу завдання'**
  String get scannerNoJobAddress;

  /// No description provided for @scannerNothing.
  ///
  /// In uk, this message translates to:
  /// **'Сканер нічого не віддав (у подавачі нема паперу?)'**
  String get scannerNothing;

  /// No description provided for @scannerNoPage.
  ///
  /// In uk, this message translates to:
  /// **'Сканер не віддав сторінку (HTTP {status})'**
  String scannerNoPage(int status);

  /// No description provided for @notJpeg.
  ///
  /// In uk, this message translates to:
  /// **'Сканер віддав не JPEG'**
  String get notJpeg;

  /// No description provided for @scanFileName.
  ///
  /// In uk, this message translates to:
  /// **'Скан {date}'**
  String scanFileName(String date);

  /// No description provided for @scanTitle.
  ///
  /// In uk, this message translates to:
  /// **'Сканування · {name}'**
  String scanTitle(String name);

  /// No description provided for @feederHint.
  ///
  /// In uk, this message translates to:
  /// **'Поклади аркуші в подавач\nі натисни «Сканувати» — відскануються всі'**
  String get feederHint;

  /// No description provided for @glassHint.
  ///
  /// In uk, this message translates to:
  /// **'Поклади аркуш на скло лицем донизу\nі натисни «Сканувати»'**
  String get glassHint;

  /// No description provided for @removePage.
  ///
  /// In uk, this message translates to:
  /// **'Прибрати сторінку'**
  String get removePage;

  /// No description provided for @source.
  ///
  /// In uk, this message translates to:
  /// **'Звідки'**
  String get source;

  /// No description provided for @glass.
  ///
  /// In uk, this message translates to:
  /// **'Скло'**
  String get glass;

  /// No description provided for @feeder.
  ///
  /// In uk, this message translates to:
  /// **'Подавач'**
  String get feeder;

  /// No description provided for @scanColor.
  ///
  /// In uk, this message translates to:
  /// **'Кольорове'**
  String get scanColor;

  /// No description provided for @scanGray.
  ///
  /// In uk, this message translates to:
  /// **'Сіре'**
  String get scanGray;

  /// No description provided for @scanBw.
  ///
  /// In uk, this message translates to:
  /// **'Чорно-біле'**
  String get scanBw;

  /// No description provided for @resolution.
  ///
  /// In uk, this message translates to:
  /// **'Роздільність'**
  String get resolution;

  /// No description provided for @dpiDocs.
  ///
  /// In uk, this message translates to:
  /// **'200 dpi — документи'**
  String get dpiDocs;

  /// No description provided for @dpiPhotos.
  ///
  /// In uk, this message translates to:
  /// **'300 — фото'**
  String get dpiPhotos;

  /// No description provided for @dpiFine.
  ///
  /// In uk, this message translates to:
  /// **'600 — дрібні деталі (довго й великий файл)'**
  String get dpiFine;

  /// No description provided for @scanning.
  ///
  /// In uk, this message translates to:
  /// **'Сканую…'**
  String get scanning;

  /// No description provided for @scanningPages.
  ///
  /// In uk, this message translates to:
  /// **'Сканую… {count} стор.'**
  String scanningPages(int count);

  /// No description provided for @scanMore.
  ///
  /// In uk, this message translates to:
  /// **'Сканувати ще'**
  String get scanMore;

  /// No description provided for @scanAnotherPage.
  ///
  /// In uk, this message translates to:
  /// **'Сканувати ще сторінку'**
  String get scanAnotherPage;

  /// No description provided for @format.
  ///
  /// In uk, this message translates to:
  /// **'Формат'**
  String get format;

  /// No description provided for @pagesToOnePdf.
  ///
  /// In uk, this message translates to:
  /// **'{count} стор. → один PDF'**
  String pagesToOnePdf(int count);

  /// No description provided for @pagesToFiles.
  ///
  /// In uk, this message translates to:
  /// **'{count, plural, one{{count} стор. → {count} {format}-файл} few{{count} стор. → {count} {format}-файли} many{{count} стор. → {count} {format}-файлів} other{{count} стор. → {count} {format}-файлу}}'**
  String pagesToFiles(int count, String format);

  /// No description provided for @shareFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося поділитися: {error}'**
  String shareFailed(String error);

  /// No description provided for @saveFailed.
  ///
  /// In uk, this message translates to:
  /// **'Не вдалося зберегти: {error}'**
  String saveFailed(String error);

  /// No description provided for @saveFailedUseShare.
  ///
  /// In uk, this message translates to:
  /// **'Зберегти не вийшло — скористайся «Поділитися»'**
  String get saveFailedUseShare;

  /// No description provided for @savedTo.
  ///
  /// In uk, this message translates to:
  /// **'Збережено: {path}'**
  String savedTo(String path);

  /// No description provided for @savedFiles.
  ///
  /// In uk, this message translates to:
  /// **'{count, plural, one{Збережено {count} файл у {folder}} few{Збережено {count} файли у {folder}} many{Збережено {count} файлів у {folder}} other{Збережено {count} файлу у {folder}}}'**
  String savedFiles(int count, String folder);

  /// No description provided for @bwAsPng.
  ///
  /// In uk, this message translates to:
  /// **' (чорно-білі сторінки — у PNG)'**
  String get bwAsPng;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return L10nEn();
    case 'uk':
      return L10nUk();
  }

  throw FlutterError(
      'L10n.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
