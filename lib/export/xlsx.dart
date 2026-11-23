import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One tab of a workbook: its [name] and [rows] (the first is the header,
/// shown bold and kept in view while scrolling).
typedef XlsxSheet = ({String name, List<List<String>> rows});

/// [sheets] as an Excel workbook (.xlsx), one tab each, in order. Opens in
/// Excel, Numbers and Google Sheets (File → Import keeps every tab).
///
/// Every cell is text. Tab names are made valid for Excel: at most 31
/// characters, none of `[]:*?/\`, never blank, and no two alike (ignoring
/// case).
Uint8List toXlsx(List<XlsxSheet> sheets) {
  final names = xlsxSheetNames([for (final s in sheets) s.name]);
  final zip = Archive();
  void add(String path, String xml) {
    final bytes = utf8.encode(xml);
    zip.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join('\n')}
</Types>''');
  add('_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');
  add('xl/workbook.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>
${[for (final (i, name) in names.indexed) '<sheet name="${_escape(name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join('\n')}
</sheets>
</workbook>''');
  add('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${[for (var i = 1; i <= sheets.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join('\n')}
<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''');
  // Style 1: bold (the header). Style 2: wrapped, at the top (the rest,
  // so multi-line cells like subtasks show every line).
  add('xl/styles.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="3">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''');
  for (final (i, sheet) in sheets.indexed) {
    add('xl/worksheets/sheet${i + 1}.xml', _sheet(sheet.rows));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(zip));
}

String _sheet(List<List<String>> rows) {
  final columns = rows.fold(0, (n, r) => r.length > n ? r.length : n);
  // Each column about as wide as its longest line, within reason.
  final widths = [
    for (var c = 0; c < columns; c++)
      rows
              .map((r) => c < r.length ? r[c] : '')
              .expand((v) => v.split('\n'))
              .fold(6, (w, line) => line.length > w ? line.length : w)
              .clamp(6, 60) +
          2,
  ];
  final out = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<sheetViews><sheetView workbookViewId="0">'
    '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
    '</sheetView></sheetViews>',
  );
  if (columns > 0) {
    out.write('<cols>');
    for (final (c, w) in widths.indexed) {
      out.write(
        '<col min="${c + 1}" max="${c + 1}" width="$w" customWidth="1"/>',
      );
    }
    out.write('</cols>');
  }
  out.write('<sheetData>');
  for (final (r, row) in rows.indexed) {
    out.write('<row r="${r + 1}">');
    for (final (c, value) in row.indexed) {
      out.write(
        '<c r="${xlsxColumn(c)}${r + 1}" s="${r == 0 ? 1 : 2}" t="inlineStr">'
        '<is><t xml:space="preserve">${_escape(value)}</t></is></c>',
      );
    }
    out.write('</row>');
  }
  out.write('</sheetData></worksheet>');
  return out.toString();
}

/// A column's letters: 0 → A, 25 → Z, 26 → AA.
String xlsxColumn(int index) {
  var n = index + 1;
  var name = '';
  while (n > 0) {
    final rem = (n - 1) % 26;
    name = String.fromCharCode(65 + rem) + name;
    n = (n - 1) ~/ 26;
  }
  return name;
}

/// [names] made into valid, distinct Excel tab names (see [toXlsx]).
List<String> xlsxSheetNames(List<String> names) {
  final taken = <String>{};
  return [
    for (final raw in names)
      () {
        var base = raw.replaceAll(RegExp(r'[\[\]:*?/\\]'), '-').trim();
        // Can't start or end with an apostrophe.
        base = base.replaceAll(RegExp(r"^'+|'+$"), '').trim();
        if (base.isEmpty) base = 'Sheet';
        var name = _clip(base, 31);
        for (var n = 2; !taken.add(name.toLowerCase()); n++) {
          final suffix = ' ($n)';
          name = '${_clip(base, 31 - suffix.length)}$suffix';
        }
        return name;
      }(),
  ];
}

String _clip(String s, int max) =>
    s.length <= max ? s : s.substring(0, max).trimRight();

/// [s] safe in XML text or an attribute; drops control characters XML
/// can't hold (keeping tabs and line breaks).
String _escape(String s) => s
    .replaceAll(RegExp('[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
