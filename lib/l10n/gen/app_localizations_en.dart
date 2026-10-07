// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'KamiDrop';

  @override
  String get cancel => 'Cancel';

  @override
  String get cancelling => 'Cancelling…';

  @override
  String get done => 'Done';

  @override
  String get add => 'Add';

  @override
  String get remove => 'Remove';

  @override
  String get tryAgain => 'Try again';

  @override
  String get settings => 'Settings';

  @override
  String get color => 'Color';

  @override
  String get duplex => 'Duplex';

  @override
  String get blackWhiteShort => 'B&W';

  @override
  String get scan => 'Scan';

  @override
  String get share => 'Share';

  @override
  String get save => 'Save';

  @override
  String get printShort => 'Print';

  @override
  String get error => 'Error';

  @override
  String get no => 'No';

  @override
  String get turnOn => 'Turn on';

  @override
  String get later => 'Later';

  @override
  String get update => 'Update';

  @override
  String get check => 'Check';

  @override
  String get checking => 'Checking…';

  @override
  String mm(int n) {
    return '$n mm';
  }

  @override
  String sizeCm(String w, String h) {
    return '$w × $h cm';
  }

  @override
  String get printersNearby => 'Printers nearby';

  @override
  String get searchingNearby => 'Looking for printers nearby…';

  @override
  String get searchAgain => 'Search again';

  @override
  String get searchingPrinters => 'Looking for printers…';

  @override
  String get noPrintersYet => 'No printers found yet';

  @override
  String get noPrintersHint =>
      'Make sure the printer is on and on the same Wi-Fi network.\nPull the list down to search again.';

  @override
  String get addPrinterByIp => 'Add a printer by IP address';

  @override
  String get printerByIp => 'Printer by IP';

  @override
  String get pickPrinterBelow => 'Pick a printer below';

  @override
  String get removeFile => 'Remove file';

  @override
  String get lastUsed => 'last used';

  @override
  String get justPoweredOn => 'Just turned on — may still be warming up';

  @override
  String scannerAt(String host) {
    return 'Scanner · $host';
  }

  @override
  String searchFailed(String error) {
    return 'Network search failed: $error';
  }

  @override
  String get unknownPrinter => 'Unknown printer';

  @override
  String updateAvailable(String version) {
    return 'Version $version is available';
  }

  @override
  String updateDownloading(String version, int percent) {
    return 'Downloading version $version… $percent%';
  }

  @override
  String updateInstalling(String version) {
    return 'Installing version $version…';
  }

  @override
  String updateInstallFailed(String error) {
    return 'Couldn\'t install: $error';
  }

  @override
  String updateCheckFailed(String error) {
    return 'Couldn\'t check for updates: $error';
  }

  @override
  String updateDownloadFailed(String error) {
    return 'Couldn\'t download the update: $error';
  }

  @override
  String get updateAllowInstall =>
      'Allow KamiDrop to install apps, then tap “Update” again';

  @override
  String get autoOpenTitle => 'Open printing right away';

  @override
  String get autoOpenSubtitle =>
      'A file from “Share” opens on the last used printer (or on the only one, if there\'s just one)';

  @override
  String get lastFirstTitle => 'Last used printer first';

  @override
  String get lastFirstSubtitle =>
      'Put the printer you used last at the top of the list';

  @override
  String get rememberLayoutTitle => 'Remember layout';

  @override
  String get rememberLayoutSubtitle =>
      'Photos and documents open with the layout of your last print instead of the default';

  @override
  String get checkUpdatesTitle => 'Check for updates';

  @override
  String get checkUpdatesSubtitle =>
      'Once a day, check whether there\'s a new version of KamiDrop. Installing only happens when you tap';

  @override
  String get upToDate => 'You have the latest version';

  @override
  String updateOnMainScreen(String version) {
    return 'Version $version is available — update from the main screen';
  }

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get gallery => 'Gallery';

  @override
  String get galleryHint => 'Photos and images';

  @override
  String get files => 'Files';

  @override
  String get filesHint => 'PDFs and images from your files';

  @override
  String galleryFailed(String error) {
    return 'Couldn\'t get photos from the gallery: $error';
  }

  @override
  String get pdfAndImages => 'PDFs and images';

  @override
  String get images => 'Images';

  @override
  String get gettingCaps => 'Getting printer capabilities…';

  @override
  String get capsUnknown => 'Printer capabilities unknown';

  @override
  String get pagesLabel => 'Pages';

  @override
  String pagesHint(int count) {
    return 'all $count, or e.g. 1-3, 5';
  }

  @override
  String pagesError(int count) {
    return 'Numbers from 1 to $count';
  }

  @override
  String get onlyBw => 'This printer only prints black and white';

  @override
  String get duplexPrint => 'Two-sided printing';

  @override
  String get notSupported => 'Not supported';

  @override
  String get copies => 'Copies';

  @override
  String get pickFileFirst => 'Choose a file first';

  @override
  String get print => 'Print';

  @override
  String printPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Print $count pages',
      one: 'Print 1 page',
    );
    return '$_temp0';
  }

  @override
  String get testPage => 'Test page';

  @override
  String get noUrfShort => 'The printer doesn\'t support AirPrint raster';

  @override
  String get opening => 'Opening…';

  @override
  String get chooseFile => 'Choose a file';

  @override
  String pagesTapToChange(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0 · tap to change';
  }

  @override
  String get pdfOrImage => 'PDF or image';

  @override
  String get layoutHint =>
      'This is the second time you\'ve set the same layout. Remember it so it\'s ready next time? You can change this in Settings.';

  @override
  String get editSheets => 'Edit sheets';

  @override
  String get unitPage => 'Page';

  @override
  String get unitSheet => 'Sheet';

  @override
  String pageOf(String unit, int index, int total) {
    return '$unit $index of $total';
  }

  @override
  String pageOfSelected(String unit, int index, int pos, int count) {
    return '$unit $index · $pos of $count selected';
  }

  @override
  String get orientation => 'Orientation';

  @override
  String get orientationAuto => 'Auto';

  @override
  String get portrait => 'Portrait';

  @override
  String get landscape => 'Landscape';

  @override
  String get size => 'Size';

  @override
  String get fit => 'Fit';

  @override
  String get fill => 'Fill';

  @override
  String get custom => 'Custom';

  @override
  String get margins => 'Margins';

  @override
  String get edgeToEdge => 'Edge to edge';

  @override
  String get minimal => 'Minimal';

  @override
  String get placement => 'Position';

  @override
  String get centered => 'Centered';

  @override
  String get top => 'Top';

  @override
  String get preparing => 'Getting ready…';

  @override
  String get cancelledBeforeSend =>
      'Cancelled — nothing was sent to the printer';

  @override
  String get jobPending => 'Queued on the printer';

  @override
  String get jobHeld => 'Held by the printer';

  @override
  String get jobProcessing => 'Printing…';

  @override
  String get jobStopped => 'Printer stopped';

  @override
  String get jobCanceled => 'Cancelled';

  @override
  String get jobAborted => 'Aborted by the printer';

  @override
  String jobState(String state) {
    return 'State: $state';
  }

  @override
  String get capsUnknownYet => 'Printer capabilities aren\'t known yet';

  @override
  String get noUrf => 'The printer doesn\'t accept AirPrint raster (image/urf)';

  @override
  String get noPagesSelected => 'No pages selected';

  @override
  String preparingPage(int page, int total) {
    return 'Preparing page $page of $total…';
  }

  @override
  String prepareError(String error) {
    return 'Preparation failed: $error';
  }

  @override
  String sendingMb(String size) {
    return 'Sending $size MB…';
  }

  @override
  String printerRejected(String details) {
    return 'The printer rejected the job ($details)';
  }

  @override
  String get sent => 'Sent';

  @override
  String get rebootedDuringPrint =>
      'The printer restarted while printing — the job was most likely lost';

  @override
  String get stoppedResponding =>
      'The printer stopped responding — check whether it printed';

  @override
  String get sentNoStatus => 'Sent (job status unavailable)';

  @override
  String get sentStillPrinting => 'Sent (the printer is still working)';

  @override
  String get printerSilentWaiting => 'The printer isn\'t responding, waiting…';

  @override
  String get jobCancelledMayPrint =>
      'Job cancelled. A sheet that was already printing may still come out';

  @override
  String get tooLateToCancel =>
      'Too late — the printer has already finished this job';

  @override
  String printerDidNotCancel(String details) {
    return 'The printer didn\'t cancel the job ($details)';
  }

  @override
  String cancelFailed(String error) {
    return 'Couldn\'t cancel: $error';
  }

  @override
  String get printerNotResponding =>
      'The printer isn\'t responding. Try restarting it.';

  @override
  String noConnectionPrinter(String error) {
    return 'Can\'t connect to the printer: $error';
  }

  @override
  String printerDroppedConnection(String error) {
    return 'The printer closed the connection: $error';
  }

  @override
  String printerErrorStatus(String status) {
    return 'The printer replied with error $status';
  }

  @override
  String get unknownIppError => 'Unknown IPP error';

  @override
  String formatNotSupported(String ext) {
    return 'The “.$ext” format isn\'t supported yet. Use a PDF or an image.';
  }

  @override
  String pdfOpenFailed(String error) {
    return 'Couldn\'t open the PDF: $error';
  }

  @override
  String pageRenderFailed(int page) {
    return 'Couldn\'t render page $page';
  }

  @override
  String imageReadFailed(String error) {
    return 'Couldn\'t read the image: $error';
  }

  @override
  String collageName(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sheet with $count photos',
      one: 'Sheet with 1 photo',
    );
    return '$_temp0';
  }

  @override
  String get photo => 'Photo';

  @override
  String get collageTitle => 'Photo sheet';

  @override
  String get addPhotos => 'Add photos';

  @override
  String get firstSheet => 'This is the first sheet';

  @override
  String photoOnSheet(int n) {
    return 'Photo moved to sheet $n';
  }

  @override
  String get cropHint =>
      'Cropping: drag the photo inside the frame, pinch to zoom';

  @override
  String get noCrop => 'No cropping';

  @override
  String get rotate => 'Rotate';

  @override
  String get whole => 'Whole';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get collageHint =>
      'Double-tap to crop · hold a photo and swipe with another finger to move it to another sheet';

  @override
  String get scannerDefaultName => 'Scanner';

  @override
  String get scannerNotResponding => 'The scanner isn\'t responding';

  @override
  String noConnectionScanner(String error) {
    return 'Can\'t connect to the scanner: $error';
  }

  @override
  String get scannerBusy => 'The scanner is busy — try again in a minute';

  @override
  String get scannerUnsupportedSettings =>
      'The scanner doesn\'t support these settings (or the feeder is empty)';

  @override
  String scannerRejected(int status) {
    return 'The scanner rejected the job (HTTP $status)';
  }

  @override
  String get scannerNoJobAddress =>
      'The scanner didn\'t report the job address';

  @override
  String get scannerNothing =>
      'The scanner returned nothing (is the feeder empty?)';

  @override
  String scannerNoPage(int status) {
    return 'The scanner didn\'t return the page (HTTP $status)';
  }

  @override
  String get notJpeg => 'The scanner didn\'t return a JPEG';

  @override
  String scanFileName(String date) {
    return 'Scan $date';
  }

  @override
  String scanTitle(String name) {
    return 'Scanning · $name';
  }

  @override
  String get feederHint =>
      'Put the sheets in the feeder\nand tap “Scan” — all of them will be scanned';

  @override
  String get glassHint =>
      'Place the sheet face down on the glass\nand tap “Scan”';

  @override
  String get removePage => 'Remove page';

  @override
  String get source => 'Source';

  @override
  String get glass => 'Glass';

  @override
  String get feeder => 'Feeder';

  @override
  String get scanColor => 'Color';

  @override
  String get scanGray => 'Grayscale';

  @override
  String get scanBw => 'Black & white';

  @override
  String get resolution => 'Resolution';

  @override
  String get dpiDocs => '200 dpi — documents';

  @override
  String get dpiPhotos => '300 — photos';

  @override
  String get dpiFine => '600 — fine detail (slow, large file)';

  @override
  String get scanning => 'Scanning…';

  @override
  String scanningPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Scanning… $count pages',
      one: 'Scanning… 1 page',
    );
    return '$_temp0';
  }

  @override
  String get scanMore => 'Scan more';

  @override
  String get scanAnotherPage => 'Scan another page';

  @override
  String get format => 'Format';

  @override
  String pagesToOnePdf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages → one PDF',
      one: '1 page → one PDF',
    );
    return '$_temp0';
  }

  @override
  String pagesToFiles(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages → $count $format files',
      one: '1 page → 1 $format file',
    );
    return '$_temp0';
  }

  @override
  String shareFailed(String error) {
    return 'Couldn\'t share: $error';
  }

  @override
  String saveFailed(String error) {
    return 'Couldn\'t save: $error';
  }

  @override
  String get saveFailedUseShare => 'Couldn\'t save — use “Share” instead';

  @override
  String savedTo(String path) {
    return 'Saved: $path';
  }

  @override
  String savedFiles(int count, String folder) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Saved $count files to $folder',
      one: 'Saved 1 file to $folder',
    );
    return '$_temp0';
  }

  @override
  String get bwAsPng => ' (black-and-white pages as PNG)';
}
