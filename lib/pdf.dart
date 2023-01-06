// Fuzzy text matcher for entity/ persn screening.
// Copyright (c) 2022, Yako.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';
import 'dart:typed_data';

// import 'package:convert/convert.dart';
// import 'package:fmatch/fmatch.dart';
// import 'package:json2yaml/json2yaml.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fmscreen.dart';

Future<Uint8List> generateDocument(ScreeningResult result,
    [PdfPageFormat format = PdfPageFormat.a4]) async {
  final doc = pw.Document(pageMode: PdfPageMode.outlines);

  final font0 = pw.Font.ttf(ByteData.sublistView(
      File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync()));
  final font1 = pw.Font.ttf(ByteData.sublistView(
      File('assets/fonts/NotoSansSC-Regular.ttf').readAsBytesSync()));
  final font2 = pw.Font.ttf(ByteData.sublistView(
      File('assets/fonts/NotoSansTC-Regular.ttf').readAsBytesSync()));
  final font3 = pw.Font.ttf(ByteData.sublistView(
      File('assets/fonts/NotoSansJP-Regular.ttf').readAsBytesSync()));

  doc.addPage(
    pw.MultiPage(
      theme: pw.ThemeData.withFont(
        base: font3,
        fontFallback: [font0, font1, font2],
      ),
      pageFormat: format.copyWith(marginBottom: 1.5 * PdfPageFormat.cm),
      orientation: pw.PageOrientation.portrait,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      header: (pw.Context context) {
        return pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(bottom: 3.0 * PdfPageFormat.mm),
          padding: const pw.EdgeInsets.only(bottom: 3.0 * PdfPageFormat.mm),
          decoration: const pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'JunoScreen',
                style: pw.Theme.of(context)
                    .defaultTextStyle
                    .copyWith(color: PdfColors.grey),
              ),
              pw.Text(
                'Screening Result',
                style: pw.Theme.of(context)
                    .defaultTextStyle
                    .copyWith(color: PdfColors.grey),
              ),
            ],
          ),
        );
      },
      footer: (pw.Context context) {
        return pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 1.0 * PdfPageFormat.cm),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.Theme.of(context)
                .defaultTextStyle
                .copyWith(color: PdfColors.grey),
          ),
        );
      },
      build: (pw.Context context) => <pw.Widget>[
        pw.Header(
          level: 2,
          title: 'Screeing Status',
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text('Screening Status', textScaleFactor: 2),
            ],
          ),
        ),
        pw.Paragraph(text: 'Input string: ${result.queryStatus.inputString}'),
        pw.Paragraph(text: 'Normalized Name: ${result.queryStatus.rawQuery}'),
        pw.Paragraph(
            text:
                'Preprocessed Name: |${result.queryStatus.terms.map((e) => '${e.string}|').join()}'),
        pw.Paragraph(
            text:
                'Query Score: ${(result.queryStatus.queryScore * 100).floor()}'),
        pw.Paragraph(
            text:
                'Screening Date/ Time: ${result.queryStatus.start.toUtc().toIso8601String()}'),
        pw.Paragraph(
            text: 'Database Version: ${result.queryStatus.databaseVersion}'),
        pw.Paragraph(
            text: 'Number of Detected Items: ${result.detectedItems.length}'),
        pw.Header(
          level: 2,
          title: 'Detected Items',
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text('Detected Items', textScaleFactor: 2),
            ],
          ),
        ),
        pw.Table.fromTextArray(
          context: context,
          columnWidths: {
            0: pw.IntrinsicColumnWidth(),
            1: pw.IntrinsicColumnWidth(),
            2: pw.IntrinsicColumnWidth(),
            3: pw.FlexColumnWidth(),
          },
          data: [...itemList(result)],
        ),
        // pw.Signature( // needs paid library
        //   name: 'JunoScreen',
        //   value: PdfSign(
        //     privateKey:
        //         PdfSign.pemPrivateKey(File('key.pem').readAsStringSync()),
        //     certificates: <Uint8List>[
        //       PdfSign.pemCertificate(File('cert.pem').readAsStringSync()),
        //     ],
        //   ),
        // ),
      ],
    ),
  );
/*
  doc.addPage(
    pw.MultiPage(
      theme: pw.ThemeData.withFont(
        base: font1,
        bold: font2,
      ),
      pageFormat: format.copyWith(marginBottom: 1.5 * PdfPageFormat.cm),
      orientation: pw.PageOrientation.portrait,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      header: (pw.Context context) {
        return pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(bottom: 3.0 * PdfPageFormat.mm),
          padding: const pw.EdgeInsets.only(bottom: 3.0 * PdfPageFormat.mm),
          decoration: const pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey))),
          child: pw.Text(
            'Screening Result',
            style: pw.Theme.of(context)
                .defaultTextStyle
                .copyWith(color: PdfColors.grey),
          ),
        );
      },
      footer: (pw.Context context) {
        return pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 1.0 * PdfPageFormat.cm),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.Theme.of(context)
                .defaultTextStyle
                .copyWith(color: PdfColors.grey),
          ),
        );
      },
      build: (pw.Context context) => <pw.Widget>[
        pw.Header(
          level: 2,
          title: 'Details of Detected Items',
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text('Details of Detected Items', textScaleFactor: 2),
            ],
          ),
        ),
        pw.Column(children: [...itemDetails(result)]),
      ],
    ),
  );
*/
  return await doc.save();
}

Iterable<List<String>> itemList(ScreeningResult result) sync* {
  var queryScore = result.queryStatus.queryScore;
  yield ['#', 'Score', 'Code', 'Best Mached Name of eacch item'];
  var index = 1;
  for (var item in result.detectedItems) {
    var bestName = item.matchedNames[0];
    yield [
      index.toString(),
      (bestName.score / queryScore * 100).floor().toString(),
      item.listCode.toString(),
      bestName.entry.string,
    ];
    index++;
  }
}
/*
Iterable<pw.Column> itemDetails(ScreeningResult result) sync* {
//    return json2yaml(jsonObject.cast<String, dynamic>()).trimRight();
  var index = 1;
  for (var item in result.detectedItems) {
    yield pw.Column(
      children: [
        pw.Table(
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
          columnWidths: {1: pw.FlexColumnWidth()},
          children: [
            pw.TableRow(children: [pw.Text('Matched Names of Item #$index')]),
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: pw.EdgeInsets.all(10),
                  child: matchedNames(item.matchedNames),
                ),
              ],
            ),
            pw.TableRow(children: [pw.Text('Body of Item #$index')]),
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: pw.EdgeInsets.all(10),
                  child: itemBody(item.body!),
                ),
              ],
            ),
          ],
        ),
        pw.Paragraph(text: ''),
      ],
    );
    index++;
  }
}

pw.Table matchedNames(List<MatchedEntry> matchedNames) {
  return pw.Table(
    border: pw.TableBorder.all(),
    columnWidths: {
      0: pw.IntrinsicColumnWidth(),
      1: pw.FlexColumnWidth(),
    },
    children: [
      pw.TableRow(children: [
        pw.Paragraph(margin: pw.EdgeInsets.all(4), text: 'Score'),
        pw.Paragraph(margin: pw.EdgeInsets.all(4), text: 'Matched Names'),
      ]),
      for (var name in matchedNames)
        pw.TableRow(
          children: [
            pw.Paragraph(
                margin: pw.EdgeInsets.all(4),
                text: (name.score * 100).floor().toString()),
            pw.Paragraph(margin: pw.EdgeInsets.all(4), text: name.entry.string),
          ],
        ),
    ],
  );
}

pw.Paragraph itemBody(Map<String, dynamic> body) {
  var yaml = json2yaml(body).trimRight();
  return pw.Paragraph(
      margin: pw.EdgeInsets.all(4),
      style: pw.TextStyle(lineSpacing: 1.0),
      text: yaml);
}
*/
