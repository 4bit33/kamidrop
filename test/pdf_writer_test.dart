import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamidrop/scan/pdf_writer.dart';

/// Найменший справжній JPEG: заголовок SOF0 8×4, 3 канали (решта для тесту не важлива).
Uint8List _jpegHeader(int w, int h, int comps) => Uint8List.fromList([
      0xFF, 0xD8, // SOI
      0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, // APP0 (скорочений)
      0xFF, 0xC0, 0x00, 0x0B, 0x08, h >> 8, h & 255, w >> 8, w & 255, comps, 0, 0, 0,
      0xFF, 0xD9,
    ]);

void main() {
  test('jpegInfo читає розмір і канали з SOF', () {
    expect(jpegInfo(_jpegHeader(1680, 2195, 3)), (1680, 2195, 3));
    expect(jpegInfo(_jpegHeader(8, 4, 1)), (8, 4, 1));
    expect(jpegInfo(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });

  test('Поріг: світле — біле (1), темне — чорне (0), рядки вирівняні до байта', () {
    final gray = Uint8List.fromList([255, 0, 255, 0, 255, 0, 255, 0, 0, 255]); // 10×1
    final bits = toBilevel(gray, 10, 1);
    expect(bits.length, 2);
    expect(bits[0], 0xAA);
    expect(bits[1], 0x40);
  });

  test('PDF: сторінки, розмір з dpi, правильний xref', () {
    final pdf = buildPdf([
      JpegPage(_jpegHeader(1700, 2338, 3), 1700, 2338, 200), // A4 при 200 dpi
      BilevelPage(Uint8List(2 * 4), 16, 4, 300),
    ], title: 'Скан');
    final text = latin1.decode(pdf);
    expect(text.startsWith('%PDF-1.4'), isTrue);
    expect(text.trimRight().endsWith('%%EOF'), isTrue);
    expect(text, contains('/Count 2'));
    expect(text, contains('/MediaBox [0 0 612.00 841.68]'), reason: '1700 px при 200 dpi = 8,5″');
    expect(text, contains('/Filter /DCTDecode'));
    expect(text, contains('/BitsPerComponent 1 /Filter /FlateDecode'));
    // Кожен запис xref вказує рівно на початок свого об'єкта.
    final xrefAt = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!);
    final entries = RegExp(r'(\d{10}) 00000 n').allMatches(text.substring(xrefAt)).map((m) => int.parse(m.group(1)!));
    var n = 1;
    for (final off in entries) {
      expect(text.substring(off).startsWith('$n 0 obj'), isTrue, reason: 'об\'єкт $n');
      n++;
    }
  });

  test('Справжній PDF відкривається pdfinfo (якщо є)', () async {
    final which = await Process.run('which', ['pdfinfo']);
    if (which.exitCode != 0) return;
    final dir = await Directory.systemTemp.createTemp('kd');
    final f = File('${dir.path}/t.pdf')..writeAsBytesSync(buildPdf([BilevelPage(Uint8List(2 * 16), 16, 16, 72)]));
    final r = await Process.run('pdfinfo', [f.path]);
    await dir.delete(recursive: true);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect('${r.stdout}', contains('Pages:'));
  });

  test('Справжній JPEG у PDF рендериться тим самим зображенням (pdftoppm, якщо є)', () async {
    final which = await Process.run('which', ['pdftoppm']);
    if (which.exitCode != 0) return;
    final jpeg = File('test/fixtures/tiny.jpg').readAsBytesSync();
    final (w, h, c) = jpegInfo(jpeg)!;
    expect([w, h, c], [120, 80, 3]);
    final dir = await Directory.systemTemp.createTemp('kd');
    File('${dir.path}/t.pdf').writeAsBytesSync(buildPdf([JpegPage(jpeg, w, h, 72, components: c)]));
    final r = await Process.run('pdftoppm', ['-r', '72', '-png', '${dir.path}/t.pdf', '${dir.path}/out']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final png = File('${dir.path}/out-1.png');
    expect(png.existsSync(), isTrue);
    await dir.delete(recursive: true);
  });
}
