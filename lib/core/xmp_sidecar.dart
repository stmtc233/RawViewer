import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

const _rdf = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
const _xmp = 'http://ns.adobe.com/xap/1.0/';

bool sharesXmpSidecar(String first, String second) =>
    path.withoutExtension(path.normalize(first)).toLowerCase() ==
    path.withoutExtension(path.normalize(second)).toLowerCase();

Future<File> _sidecar(String imagePath) async {
  final stem = path.withoutExtension(imagePath);
  for (final candidate in [
    '$imagePath.xmp',
    '$imagePath.XMP',
    '$stem.xmp',
    '$stem.XMP',
  ]) {
    if (await FileSystemEntity.type(candidate) !=
        FileSystemEntityType.notFound) {
      return File(candidate);
    }
  }
  return File('$stem.xmp');
}

Iterable<XmlElement> _descriptions(XmlDocument document) => document
    .findAllElements('Description', namespaceUri: _rdf)
    .where((element) =>
        element.parentElement?.localName == 'RDF' &&
        element.parentElement?.namespaceUri == _rdf &&
        (element.getAttribute('about', namespaceUri: _rdf) ?? '').isEmpty);

XmlDocument _parse(String source) {
  final document = XmlDocument.parse(source);
  if (document.findAllElements('RDF', namespaceUri: _rdf).length != 1) {
    throw const FormatException('Expected one XMP RDF container');
  }
  return document;
}

/// The same-stem sidecar is shared by RAW + JPEG pairs. Existing extension-
/// qualified sidecars take precedence, as used by editors such as darktable.
Future<Map<String, String>> readXmpSidecar(String imagePath) async {
  final file = await _sidecar(imagePath);
  if (!await file.exists()) return const {};
  final document = _parse(await file.readAsString());
  final tags = <String, String>{};
  for (final description in _descriptions(document)) {
    for (final attribute in description.attributes) {
      if (attribute.namespaceUri == _rdf ||
          attribute.name.qualified == 'xmlns' ||
          attribute.name.prefix == 'xmlns') {
        continue;
      }
      tags['XMP ${attribute.name.qualified}'] = attribute.value;
      if (attribute.localName == 'Rating' && attribute.namespaceUri == _xmp) {
        tags['Image Rating'] = attribute.value.trim();
      }
    }
    for (final element in description.childElements) {
      final items = element.findAllElements('li', namespaceUri: _rdf);
      final value = items.isEmpty
          ? element.innerText.trim()
          : items.map((item) => item.innerText.trim()).join(', ');
      tags['XMP ${element.name.qualified}'] = value;
      if (element.localName == 'Rating' && element.namespaceUri == _xmp) {
        tags['Image Rating'] = value;
      }
    }
  }
  return tags;
}

Future<void> writeXmpRating(String imagePath, int rating) async {
  if (rating < 0 || rating > 5) throw RangeError.range(rating, 0, 5, 'rating');
  if (!await File(imagePath).exists()) {
    throw FileSystemException('Image no longer exists', imagePath);
  }
  final file = await _sidecar(imagePath);
  // Never replace an unreadable or malformed sidecar with an empty packet.
  final original = await file.exists() ? await file.readAsString() : null;
  final document = _parse(original ??
      '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
          '<rdf:RDF xmlns:rdf="$_rdf">'
          '<rdf:Description rdf:about=""/>'
          '</rdf:RDF></x:xmpmeta>');
  final descriptions = _descriptions(document).toList();
  if (descriptions.isEmpty) {
    throw const FormatException('No primary XMP description');
  }
  // Update both attribute and element encodings, including alternate prefixes.
  var found = false;
  for (final description in descriptions) {
    for (final attribute in description.attributes) {
      if (attribute.localName == 'Rating' && attribute.namespaceUri == _xmp) {
        attribute.value = '$rating';
        found = true;
      }
    }
    for (final element in description.childElements) {
      if (element.localName == 'Rating' && element.namespaceUri == _xmp) {
        element.children
          ..clear()
          ..add(XmlText('$rating'));
        found = true;
      }
    }
  }
  if (!found) {
    descriptions.first.children.add(XmlElement(
        const XmlName.parts('Rating', prefix: 'xmp', namespaceUri: _xmp), [
      XmlAttribute(const XmlName.namespace(name: 'xmp'), _xmp),
    ], [
      XmlText('$rating')
    ]));
  }

  // Stage on the same filesystem, flush, then replace. A failed write leaves
  // the existing sidecar intact; the image itself is never opened for writing.
  final staging =
      await Directory(path.dirname(file.path)).createTemp('.rawviewer-xmp-');
  try {
    final temporary = File(path.join(staging.path, 'rating.xmp'));
    await temporary.writeAsString(document.toXmlString(), flush: true);
    final current = await file.exists() ? await file.readAsString() : null;
    if (current != original) {
      throw FileSystemException('XMP changed while saving', file.path);
    }
    await temporary.rename(file.path);
  } finally {
    await staging.delete(recursive: true);
  }
}
