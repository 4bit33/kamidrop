// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class L10nUk extends L10n {
  L10nUk([String locale = 'uk']) : super(locale);

  @override
  String get appTitle => 'KamiDrop';

  @override
  String get cancel => 'Скасувати';

  @override
  String get cancelling => 'Скасовую…';

  @override
  String get done => 'Готово';

  @override
  String get add => 'Додати';

  @override
  String get remove => 'Прибрати';

  @override
  String get tryAgain => 'Спробувати ще раз';

  @override
  String get settings => 'Налаштування';

  @override
  String get color => 'Колір';

  @override
  String get duplex => 'Двосторонній';

  @override
  String get blackWhiteShort => 'Ч/Б';

  @override
  String get scan => 'Сканувати';

  @override
  String get share => 'Поділитися';

  @override
  String get save => 'Зберегти';

  @override
  String get printShort => 'Друк';

  @override
  String get error => 'Помилка';

  @override
  String get no => 'Ні';

  @override
  String get turnOn => 'Увімкнути';

  @override
  String get later => 'Пізніше';

  @override
  String get update => 'Оновити';

  @override
  String get check => 'Перевірити';

  @override
  String get checking => 'Перевіряю…';

  @override
  String mm(int n) {
    return '$n мм';
  }

  @override
  String sizeCm(String w, String h) {
    return '$w × $h см';
  }

  @override
  String get printersNearby => 'Принтери поруч';

  @override
  String get searchingNearby => 'Шукаю принтери поруч…';

  @override
  String get searchAgain => 'Шукати знову';

  @override
  String get searchingPrinters => 'Шукаю принтери…';

  @override
  String get noPrintersYet => 'Принтерів поки не видно';

  @override
  String get noPrintersHint =>
      'Переконайся, що принтер увімкнений і в тій самій Wi-Fi мережі.\nПотягни список донизу, щоб шукати знову.';

  @override
  String get addPrinterByIp => 'Додати принтер за IP-адресою';

  @override
  String get printerByIp => 'Принтер за IP';

  @override
  String get pickPrinterBelow => 'Вибери принтер нижче';

  @override
  String get removeFile => 'Прибрати файл';

  @override
  String get lastUsed => 'останній';

  @override
  String get justPoweredOn => 'Щойно ввімкнувся — може ще прогріватися';

  @override
  String scannerAt(String host) {
    return 'Сканер · $host';
  }

  @override
  String searchFailed(String error) {
    return 'Пошук у мережі не вдався: $error';
  }

  @override
  String get unknownPrinter => 'Невідомий принтер';

  @override
  String updateAvailable(String version) {
    return 'Є нова версія $version';
  }

  @override
  String updateDownloading(String version, int percent) {
    return 'Завантажую версію $version… $percent %';
  }

  @override
  String updateInstalling(String version) {
    return 'Встановлюю версію $version…';
  }

  @override
  String updateInstallFailed(String error) {
    return 'Не вдалося встановити: $error';
  }

  @override
  String updateCheckFailed(String error) {
    return 'Не вдалося перевірити оновлення: $error';
  }

  @override
  String updateDownloadFailed(String error) {
    return 'Не вдалося завантажити оновлення: $error';
  }

  @override
  String get updateAllowInstall =>
      'Дозволь KamiDrop встановлювати застосунки й натисни «Оновити» ще раз';

  @override
  String get autoOpenTitle => 'Одразу відкривати друк';

  @override
  String get autoOpenSubtitle =>
      'Файл із «Поділитися» відкривається на останньому принтері (або на єдиному, якщо він один)';

  @override
  String get lastFirstTitle => 'Останній принтер першим';

  @override
  String get lastFirstSubtitle =>
      'Ставити принтер, на якому друкував востаннє, на початок списку';

  @override
  String get rememberLayoutTitle => 'Пам\'ятати макет';

  @override
  String get rememberLayoutSubtitle =>
      'Фото й документи відкриваються з макетом минулого друку, а не з типовим';

  @override
  String get checkUpdatesTitle => 'Перевіряти оновлення';

  @override
  String get checkUpdatesSubtitle =>
      'Раз на добу дивитися, чи є нова версія KamiDrop. Встановлення — лише після твого натискання';

  @override
  String get upToDate => 'Встановлено найновішу версію';

  @override
  String updateOnMainScreen(String version) {
    return 'Є версія $version — оновити можна на головному екрані';
  }

  @override
  String versionLabel(String version) {
    return 'Версія $version';
  }

  @override
  String get printServiceTitle => 'Друк з інших застосунків';

  @override
  String get printServiceSubtitle =>
      'Увімкни KamiDrop у системних налаштуваннях друку — і принтери з\'являться в «Друк» у Chrome, Фото, Gmail. Типову службу там можна вимкнути.';

  @override
  String get printServiceHintTitle => 'Друк з будь-якого застосунку';

  @override
  String get printServiceHintBody =>
      'Тепер принтери KamiDrop є в системному «Друк» — у Chrome, Фото, Gmail тощо. Щоб принтери не дублювались, вимкни в налаштуваннях друку «Стандартний сервіс друку».';

  @override
  String get printSettings => 'Налаштування друку';

  @override
  String get gotIt => 'Зрозуміло';

  @override
  String get language => 'Мова';

  @override
  String get languageSystem => 'Як у системі';

  @override
  String get gallery => 'Галерея';

  @override
  String get galleryHint => 'Фото й зображення';

  @override
  String get files => 'Файли';

  @override
  String get filesHint => 'PDF і зображення з провідника';

  @override
  String galleryFailed(String error) {
    return 'Не вдалося взяти фото з галереї: $error';
  }

  @override
  String get pdfAndImages => 'PDF і зображення';

  @override
  String get images => 'Зображення';

  @override
  String get gettingCaps => 'Отримую можливості принтера…';

  @override
  String get capsUnknown => 'Можливості принтера невідомі';

  @override
  String get pagesLabel => 'Сторінки';

  @override
  String pagesHint(int count) {
    return 'усі $count, або напр. 1-3, 5';
  }

  @override
  String pagesError(int count) {
    return 'Номери від 1 до $count';
  }

  @override
  String get onlyBw => 'Цей принтер друкує лише чорно-біле';

  @override
  String get duplexPrint => 'Двосторонній друк';

  @override
  String get notSupported => 'Не підтримується';

  @override
  String get copies => 'Копії';

  @override
  String get pickFileFirst => 'Спершу вибери файл';

  @override
  String get print => 'Друкувати';

  @override
  String printPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Друкувати $count сторінки',
      many: 'Друкувати $count сторінок',
      few: 'Друкувати $count сторінки',
      one: 'Друкувати $count сторінку',
    );
    return '$_temp0';
  }

  @override
  String get testPage => 'Тестова сторінка';

  @override
  String get noUrfShort => 'Принтер не підтримує AirPrint-растр';

  @override
  String get opening => 'Відкриваю…';

  @override
  String get chooseFile => 'Вибрати файл';

  @override
  String pagesTapToChange(int count) {
    return '$count стор. · натисни, щоб змінити';
  }

  @override
  String get pdfOrImage => 'PDF або зображення';

  @override
  String get layoutHint =>
      'Ти вже вдруге ставиш той самий макет. Запам\'ятовувати його, щоб наступного разу він був одразу? Це можна змінити в налаштуваннях.';

  @override
  String get editSheets => 'Редагувати аркуші';

  @override
  String get unitPage => 'Сторінка';

  @override
  String get unitSheet => 'Аркуш';

  @override
  String pageOf(String unit, int index, int total) {
    return '$unit $index з $total';
  }

  @override
  String pageOfSelected(String unit, int index, int pos, int count) {
    return '$unit $index · $pos з $count вибраних';
  }

  @override
  String get orientation => 'Орієнтація';

  @override
  String get orientationAuto => 'Авто';

  @override
  String get portrait => 'Книжкова';

  @override
  String get landscape => 'Альбомна';

  @override
  String get size => 'Розмір';

  @override
  String get fit => 'Вписати';

  @override
  String get fill => 'Заповнити';

  @override
  String get custom => 'Свій';

  @override
  String get margins => 'Поля';

  @override
  String get edgeToEdge => 'До краю';

  @override
  String get minimal => 'Мінімальні';

  @override
  String get placement => 'Розташування';

  @override
  String get centered => 'По центру';

  @override
  String get top => 'Вгорі';

  @override
  String get preparing => 'Готуюсь…';

  @override
  String get cancelledBeforeSend =>
      'Скасовано — на принтер нічого не надіслано';

  @override
  String get jobPending => 'У черзі принтера';

  @override
  String get jobHeld => 'Утримується принтером';

  @override
  String get jobProcessing => 'Друкується…';

  @override
  String get jobStopped => 'Принтер зупинився';

  @override
  String get jobCanceled => 'Скасовано';

  @override
  String get jobAborted => 'Перервано принтером';

  @override
  String jobState(String state) {
    return 'Стан: $state';
  }

  @override
  String get capsUnknownYet => 'Можливості принтера ще не відомі';

  @override
  String get noUrf => 'Принтер не приймає AirPrint-растр (image/urf)';

  @override
  String get noPagesSelected => 'Не вибрано жодної сторінки';

  @override
  String preparingPage(int page, int total) {
    return 'Готую сторінку $page з $total…';
  }

  @override
  String prepareError(String error) {
    return 'Помилка підготовки: $error';
  }

  @override
  String sendingMb(String size) {
    return 'Надсилаю $size МБ…';
  }

  @override
  String printerRejected(String details) {
    return 'Принтер відхилив завдання ($details)';
  }

  @override
  String get sent => 'Надіслано';

  @override
  String get rebootedDuringPrint =>
      'Принтер перезавантажився під час друку — завдання, найпевніше, втрачено';

  @override
  String get stoppedResponding =>
      'Принтер перестав відповідати — перевір, чи надрукувалось';

  @override
  String get sentNoStatus => 'Надіслано (статус завдання недоступний)';

  @override
  String get sentStillPrinting => 'Надіслано (принтер ще працює)';

  @override
  String get printerSilentWaiting => 'Принтер не відповідає, чекаю…';

  @override
  String get jobCancelledMayPrint =>
      'Завдання скасовано. Аркуш, що вже друкувався, може вийти';

  @override
  String get tooLateToCancel => 'Запізно — принтер уже завершив це завдання';

  @override
  String printerDidNotCancel(String details) {
    return 'Принтер не скасував завдання ($details)';
  }

  @override
  String cancelFailed(String error) {
    return 'Не вдалося скасувати: $error';
  }

  @override
  String get printerNotResponding =>
      'Принтер не відповідає. Спробуй його перезавантажити.';

  @override
  String noConnectionPrinter(String error) {
    return 'Немає з\'єднання з принтером: $error';
  }

  @override
  String printerDroppedConnection(String error) {
    return 'Принтер розірвав з\'єднання: $error';
  }

  @override
  String printerErrorStatus(String status) {
    return 'Принтер відповів помилкою $status';
  }

  @override
  String get unknownIppError => 'Невідома помилка IPP';

  @override
  String formatNotSupported(String ext) {
    return 'Формат «.$ext» поки не підтримується. Можна PDF або зображення.';
  }

  @override
  String pdfOpenFailed(String error) {
    return 'Не вдалося відкрити PDF: $error';
  }

  @override
  String pageRenderFailed(int page) {
    return 'Не вдалося відрендерити сторінку $page';
  }

  @override
  String imageReadFailed(String error) {
    return 'Не вдалося прочитати зображення: $error';
  }

  @override
  String collageName(int count) {
    return 'Аркуш із $count фото';
  }

  @override
  String get photo => 'Фото';

  @override
  String get collageTitle => 'Аркуш із фото';

  @override
  String get addPhotos => 'Додати фото';

  @override
  String get firstSheet => 'Це перший аркуш';

  @override
  String photoOnSheet(int n) {
    return 'Фото на аркуші $n';
  }

  @override
  String get cropHint =>
      'Кадрування: тягни фото в рамці, двома пальцями — ближче';

  @override
  String get noCrop => 'Без обрізки';

  @override
  String get rotate => 'Повернути';

  @override
  String get whole => 'Ціле';

  @override
  String get duplicate => 'Копія';

  @override
  String get collageHint =>
      'Подвійний тап — кадрувати · тримай фото й свайпни іншим пальцем — на інший аркуш';

  @override
  String get scannerDefaultName => 'Сканер';

  @override
  String get scannerNotResponding => 'Сканер не відповідає';

  @override
  String noConnectionScanner(String error) {
    return 'Немає з\'єднання зі сканером: $error';
  }

  @override
  String get scannerBusy => 'Сканер зайнятий — спробуй за хвилину';

  @override
  String get scannerUnsupportedSettings =>
      'Сканер не підтримує такі налаштування (або в подавачі нема паперу)';

  @override
  String scannerRejected(int status) {
    return 'Сканер відхилив завдання (HTTP $status)';
  }

  @override
  String get scannerNoJobAddress => 'Сканер не повідомив адресу завдання';

  @override
  String get scannerNothing =>
      'Сканер нічого не віддав (у подавачі нема паперу?)';

  @override
  String scannerNoPage(int status) {
    return 'Сканер не віддав сторінку (HTTP $status)';
  }

  @override
  String get notJpeg => 'Сканер віддав не JPEG';

  @override
  String scanFileName(String date) {
    return 'Скан $date';
  }

  @override
  String scanTitle(String name) {
    return 'Сканування · $name';
  }

  @override
  String get feederHint =>
      'Поклади аркуші в подавач\nі натисни «Сканувати» — відскануються всі';

  @override
  String get glassHint =>
      'Поклади аркуш на скло лицем донизу\nі натисни «Сканувати»';

  @override
  String get removePage => 'Прибрати сторінку';

  @override
  String get source => 'Звідки';

  @override
  String get glass => 'Скло';

  @override
  String get feeder => 'Подавач';

  @override
  String get scanColor => 'Кольорове';

  @override
  String get scanGray => 'Сіре';

  @override
  String get scanBw => 'Чорно-біле';

  @override
  String get resolution => 'Роздільність';

  @override
  String get dpiDocs => '200 dpi — документи';

  @override
  String get dpiPhotos => '300 — фото';

  @override
  String get dpiFine => '600 — дрібні деталі (довго й великий файл)';

  @override
  String get scanning => 'Сканую…';

  @override
  String scanningPages(int count) {
    return 'Сканую… $count стор.';
  }

  @override
  String get scanMore => 'Сканувати ще';

  @override
  String get scanAnotherPage => 'Сканувати ще сторінку';

  @override
  String get format => 'Формат';

  @override
  String pagesToOnePdf(int count) {
    return '$count стор. → один PDF';
  }

  @override
  String pagesToFiles(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count стор. → $count $format-файлу',
      many: '$count стор. → $count $format-файлів',
      few: '$count стор. → $count $format-файли',
      one: '$count стор. → $count $format-файл',
    );
    return '$_temp0';
  }

  @override
  String shareFailed(String error) {
    return 'Не вдалося поділитися: $error';
  }

  @override
  String saveFailed(String error) {
    return 'Не вдалося зберегти: $error';
  }

  @override
  String get saveFailedUseShare =>
      'Зберегти не вийшло — скористайся «Поділитися»';

  @override
  String savedTo(String path) {
    return 'Збережено: $path';
  }

  @override
  String savedFiles(int count, String folder) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Збережено $count файлу у $folder',
      many: 'Збережено $count файлів у $folder',
      few: 'Збережено $count файли у $folder',
      one: 'Збережено $count файл у $folder',
    );
    return '$_temp0';
  }

  @override
  String get bwAsPng => ' (чорно-білі сторінки — у PNG)';
}
