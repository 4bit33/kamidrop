// Мінімальна реалізація протоколу IPP (RFC 8010/8011): кодування запитів і розбір відповідей.
import 'dart:convert';
import 'dart:typed_data';

class IppTag {
  static const operationAttributes = 0x01;
  static const jobAttributes = 0x02;
  static const end = 0x03;
  static const printerAttributes = 0x04;

  static const integer = 0x21;
  static const boolean = 0x22;
  static const enumValue = 0x23;
  static const resolution = 0x32;
  static const rangeOfInteger = 0x33;
  static const begCollection = 0x34;
  static const textWithLanguage = 0x35;
  static const nameWithLanguage = 0x36;
  static const endCollection = 0x37;
  static const text = 0x41;
  static const name = 0x42;
  static const keyword = 0x44;
  static const memberAttrName = 0x4A;
  static const uri = 0x45;
  static const charset = 0x47;
  static const naturalLanguage = 0x48;
  static const mimeType = 0x49;
}

class IppOp {
  static const printJob = 0x0002;
  static const cancelJob = 0x0008;
  static const getJobAttributes = 0x0009;
  static const getPrinterAttributes = 0x000B;
}

class IppVersion {
  final int major, minor;
  const IppVersion(this.major, this.minor);
  static const v20 = IppVersion(2, 0);
  static const v11 = IppVersion(1, 1);
  @override
  String toString() => '$major.$minor';
}

Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v);
Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setInt32(0, v);

/// Будує IPP-запит: заголовок, групи атрибутів, кінцевий тег і (необов'язково) дані документа.
class IppRequestBuilder {
  final BytesBuilder _b = BytesBuilder(copy: false);

  IppRequestBuilder(int operation, {int requestId = 1, IppVersion version = IppVersion.v20}) {
    _b.add([version.major, version.minor, (operation >> 8) & 0xff, operation & 0xff]);
    _b.add(_u32(requestId));
  }

  /// Стандартний початок: operation-attributes з charset, мовою та printer-uri.
  factory IppRequestBuilder.standard(int operation, String printerUri,
      {int requestId = 1, IppVersion version = IppVersion.v20}) {
    return IppRequestBuilder(operation, requestId: requestId, version: version)
      ..group(IppTag.operationAttributes)
      ..string(IppTag.charset, 'attributes-charset', 'utf-8')
      ..string(IppTag.naturalLanguage, 'attributes-natural-language', 'en')
      ..string(IppTag.uri, 'printer-uri', printerUri);
  }

  void group(int tag) => _b.addByte(tag);

  void attr(int tag, String name, List<int> value) {
    final n = utf8.encode(name);
    _b.addByte(tag);
    _b.add(_u16(n.length));
    _b.add(n);
    _b.add(_u16(value.length));
    _b.add(value);
  }

  void string(int tag, String name, String value) => attr(tag, name, utf8.encode(value));

  /// Атрибут із кількома значеннями (1setOf): наступні значення мають порожнє ім'я.
  void strings(int tag, String name, List<String> values) {
    for (var i = 0; i < values.length; i++) {
      string(tag, i == 0 ? name : '', values[i]);
    }
  }

  void integer(String name, int value, {int tag = IppTag.integer}) => attr(tag, name, _u32(value));

  /// Колекція (RFC 8010 §3.1.6), напр. media-col. Значення членів: int → integer,
  /// String → keyword, Map → вкладена колекція.
  void collection(String name, Map<String, Object> members) {
    attr(IppTag.begCollection, name, const []);
    _members(members);
  }

  void _members(Map<String, Object> members) {
    members.forEach((member, value) {
      attr(IppTag.memberAttrName, '', utf8.encode(member));
      switch (value) {
        case int v:
          attr(IppTag.integer, '', _u32(v));
        case String v:
          attr(IppTag.keyword, '', utf8.encode(v));
        case Map<String, Object> v:
          attr(IppTag.begCollection, '', const []);
          _members(v);
        default:
          throw ArgumentError('Непідтримуване значення в колекції: $member = $value');
      }
    });
    attr(IppTag.endCollection, '', const []);
  }

  Uint8List build({List<int>? document}) {
    _b.addByte(IppTag.end);
    if (document != null) _b.add(document);
    return _b.takeBytes();
  }
}

class IppRange {
  final int lower, upper;
  const IppRange(this.lower, this.upper);
  @override
  String toString() => '$lower-$upper';
}

class IppResolution {
  final int x, y, units; // units: 3 = dpi, 4 = dpcm
  const IppResolution(this.x, this.y, this.units);
  @override
  String toString() => '${x}x$y${units == 3 ? 'dpi' : 'dpcm'}';
}

/// Маркер-значення для вкладених колекцій (їхній вміст поки не розбираємо).
class IppCollection {
  const IppCollection();
  @override
  String toString() => '<collection>';
}

class IppResponse {
  final int status;
  final Map<String, List<Object?>> attributes;

  IppResponse(this.status, this.attributes);

  bool get isSuccess => status <= 0x00FF;

  List<Object?> operator [](String name) => attributes[name] ?? const [];

  T? first<T>(String name) {
    for (final v in this[name]) {
      if (v is T) return v;
    }
    return null;
  }

  List<T> all<T>(String name) => this[name].whereType<T>().toList();

  String get statusHex => '0x${status.toRadixString(16).padLeft(4, '0')}';
}

/// Розбирає IPP-відповідь. Атрибути всіх груп зливаються в одну мапу;
/// вміст колекцій пропускається (саме значення позначається як [IppCollection]).
IppResponse parseIppResponse(Uint8List data) {
  if (data.length < 8) {
    throw const FormatException('IPP-відповідь закоротка');
  }
  final bd = ByteData.sublistView(data);
  final status = bd.getUint16(2);
  final attrs = <String, List<Object?>>{};
  var pos = 8;
  String? current;
  var depth = 0;

  while (pos < data.length) {
    final tag = data[pos++];
    if (tag == IppTag.end) break;
    if (tag < 0x10) {
      current = null; // початок нової групи
      continue;
    }
    if (pos + 2 > data.length) break;
    final nameLen = bd.getUint16(pos);
    pos += 2;
    if (pos + nameLen + 2 > data.length) break;
    final name = utf8.decode(Uint8List.sublistView(data, pos, pos + nameLen), allowMalformed: true);
    pos += nameLen;
    final valueLen = bd.getUint16(pos);
    pos += 2;
    if (pos + valueLen > data.length) break;
    final raw = Uint8List.sublistView(data, pos, pos + valueLen);
    pos += valueLen;

    if (tag == IppTag.begCollection) {
      if (depth == 0) {
        if (name.isNotEmpty) {
          current = name;
          attrs[name] = [];
        }
        if (current != null) attrs[current]!.add(const IppCollection());
      }
      depth++;
      continue;
    }
    if (tag == IppTag.endCollection) {
      if (depth > 0) depth--;
      continue;
    }
    if (depth > 0) continue;

    if (name.isNotEmpty) {
      current = name;
      attrs[name] = [];
    }
    if (current != null) attrs[current]!.add(_decodeValue(tag, raw));
  }
  return IppResponse(status, attrs);
}

Object? _decodeValue(int tag, Uint8List raw) {
  final bd = ByteData.sublistView(raw);
  switch (tag) {
    case IppTag.integer:
    case IppTag.enumValue:
      return raw.length == 4 ? bd.getInt32(0) : null;
    case IppTag.boolean:
      return raw.isNotEmpty && raw[0] != 0;
    case IppTag.rangeOfInteger:
      return raw.length == 8 ? IppRange(bd.getInt32(0), bd.getInt32(4)) : null;
    case IppTag.resolution:
      return raw.length == 9 ? IppResolution(bd.getInt32(0), bd.getInt32(4), raw[8]) : null;
    case IppTag.textWithLanguage:
    case IppTag.nameWithLanguage:
      if (raw.length < 4) return null;
      final langLen = bd.getUint16(0);
      if (raw.length < 4 + langLen) return null;
      final textLen = bd.getUint16(2 + langLen);
      final end = (4 + langLen + textLen).clamp(0, raw.length);
      return utf8.decode(Uint8List.sublistView(raw, 4 + langLen, end), allowMalformed: true);
  }
  if (tag >= 0x41 && tag <= 0x49) return utf8.decode(raw, allowMalformed: true);
  if (tag >= 0x10 && tag <= 0x1F) return null; // out-of-band: unsupported / unknown / no-value
  return Uint8List.fromList(raw); // octetString, dateTime тощо
}
