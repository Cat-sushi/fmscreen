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

import 'dart:convert';
import 'dart:io';

import 'package:fmatch/fmatch.dart';
import 'package:fmscreen/src/util.dart';
import 'package:html/parser.dart';

final pls = 'assets/database';

// https://www.trade.gov/consolidated-screening-list JSON
final consolidatedUri = Uri(
    scheme: 'https',
    host: 'data.trade.gov',
    path: '/downloadable_consolidated_screening_list/v1/consolidated.json');
final consolidatedJson = '$pls/consolidated.json';
final consolidatedJsonIndent = '$pls/consolidated_indent.json';

final fulUri = Uri(
    scheme: 'https', host: 'www.meti.go.jp', path: '/policy/anpo/law05.html');
final fulHtml = '$pls/ful.html';
final fulXlsx = '$pls/ful.xlsx';
final fulCsv = '$pls/ful.csv';

final concatList = '$pls/list.csv';
late final IOSink outSinkCsv;
final concatId2Body = '$pls/id2body.json';
late final IOSink outSinkJson;
var first = true;

final rBulletSplitter =
    RegExp(r'[\r\n]+ *[・･]', multiLine: true, unicode: true);
final rSemicolonSplitter = RegExp(' *; *(and;?)? *');
final rCrConnector = RegExp(r'[\r\n]', multiLine: true, unicode: true);
final rTrailCamma = RegExp(r'^(.*) *,$', unicode: true);
final rBullet = RegExp(r'^[・･] *', unicode: true);
final rDoubleQuate = RegExp(r'^["”] *(.*) *["”]$', unicode: true);
final rNewLine = RegExp(r'[\r\n]+', unicode: true);
final jsonEncoderIndent = JsonEncoder.withIndent('  ');

Future<void> main(List<String> args) async {
  var consolidatedJsonFile = File(consolidatedJson);
  var fetching = !consolidatedJsonFile.existsSync() ||
      DateTime.now()
              .difference(consolidatedJsonFile.lastModifiedSync())
              .inHours >
          24 - 1;

  if (fetching) {
    print("Fetching consolidated list.");
    await fetchConsolidated();
    print("Fetching foreign user list.");
    await fetchFul();
  }

  outSinkCsv = File(concatList).openWrite()..add(utf8Bom);
  outSinkJson = File(concatId2Body).openWrite()..writeln('[');

  print("Extracting entries from consolidated list.");
  var start = DateTime.now();
  await extConsolidated();
  await outSinkCsv.flush();
  await outSinkJson.flush();
  var end = DateTime.now();
  print(end.difference(start).inMilliseconds);
  start = end;
  print("Extracting entries from foreign user list.");
  await extFul();
  end = DateTime.now();
  print(end.difference(start).inMilliseconds);

  await outSinkCsv.close();
  outSinkJson.write('\n]');
  await outSinkJson.close();

  print("Building db and idb.");
  final matcher = FMatcher();
  await matcher.init();
}

Future<void> fetchConsolidated() async {
  var client = HttpClient();
  try {
    HttpClientRequest request = await client.getUrl(consolidatedUri);
    HttpClientResponse response = await request.close();
    var outSink = File(consolidatedJson).openWrite();
    await for (var chank in response) {
      outSink.add(chank);
    }
    await outSink.close();
  } finally {
    client.close();
  }
}

final regExpSource = RegExp(r'^.*\(([^)]+)\).*');

Future<void> extConsolidated() async {
  final jsonString = File(consolidatedJson).readAsStringSync();
  final jsonObject = jsonDecode(jsonString) as Map<String, dynamic>;
  final jsonStringIndent = jsonEncoderIndent.convert(jsonObject);
  final outSinkIndent = File(consolidatedJsonIndent).openWrite();
  outSinkIndent.write(jsonStringIndent);
  await outSinkIndent.close();
  final results = jsonObject['results'] as List<dynamic>;
  var ix = 0;
  for (var r in results) {
    ix++;
    var id = 'CONS$ix';
    var row = surpressNullAndEmptyPropertiesFromJson(r as Map<String, dynamic>)
        as Map<String, Object>;
    var listCode = row['source'] as String;
    listCode = listCode.replaceFirstMapped(regExpSource, (m) => m[1]!);
    if (listCode == 'NS-MBS List') {
      listCode = 'MBS';
    }
    var rowJson = <String, dynamic>{'id': id, 'body': row};
    var rowJsonString = jsonEncoderIndent.convert(rowJson);
    if (first) {
      first = false;
    } else {
      outSinkJson.writeln(',');
    }
    outSinkJson.write(rowJsonString);
    var name = row['name'] as String;
    name = name.replaceAll(rNewLine, ' ');
    outSinkCsv
      ..write(quoteCsvCell(normalize(name)))
      ..write(',')
      ..write(quoteCsvCell(id))
      ..write(',')
      ..write(quoteCsvCell(listCode))
      ..write('\r\n');
    var altNames = row['alt_names'] as List<dynamic>?;
    if (altNames == null) {
      continue;
    }
    for (var a in altNames) {
      var altName = a as String;
      if (altName == '') {
        continue;
      }
      var altNames2 = altName.split(rSemicolonSplitter);
      for (var a in altNames2) {
        a = a.trim();
        a = a.replaceFirstMapped(rTrailCamma, (match) => match.group(1)!);
        a = a.replaceFirstMapped(rDoubleQuate, (match) => match.group(1)!);
        if (a == '') {
          continue;
        }
        outSinkCsv
          ..write(quoteCsvCell(normalize(a)))
          ..write(',')
          ..write(quoteCsvCell(id))
          ..write(',')
          ..write(quoteCsvCell(listCode))
          ..write('\r\n');
      }
    }
  }
}

Object? surpressNullAndEmptyPropertiesFromJson(Object? json) {
  if (json == null) {
    return null;
  } else if (json is List) {
    var ret = <Object>[];
    for (var e in json) {
      var r = surpressNullAndEmptyPropertiesFromJson(e);
      if (r != null) {
        ret.add(r);
      }
    }
    if (ret.isEmpty) {
      return null;
    }
    return ret;
  } else if (json is Map) {
    var ret = <String, Object>{};
    for (var e in json.entries) {
      var r = surpressNullAndEmptyPropertiesFromJson(e.value);
      if (r != null) {
        ret[e.key] = r;
      }
    }
    if (ret.isEmpty) {
      return null;
    }
    return ret;
  } else if (json is String) {
    if (json == '') {
      return null;
    }
    return json;
  } else {
    return json;
  }
}

Future<void> fetchFul() async {
  var client = HttpClient();
  String stringData;
  try {
    HttpClientRequest request = await client.getUrl(fulUri);
    HttpClientResponse response = await request.close();
    stringData = await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
  var htmlSink = File(fulHtml).openWrite();
  htmlSink.write(stringData);
  await htmlSink.close();
  var fulHtmlSring = File(fulHtml).readAsStringSync();
  var dom = parse(fulHtmlSring);
  var elementFul = dom
      .getElementsByTagName('a')
      .where((e) => e.attributes['name'] == 'user-list')
      .first;
  var elementTbody = elementFul.parent!.parent!.parent;
  var elementFulRow = elementTbody!.children[4];
  var elementFulCol = elementFulRow.children[2];
  var ancorFulCsv = elementFulCol.getElementsByTagName('a')[2];
  var fulCsvPath = ancorFulCsv.attributes['href']!;
  final fulCsvUri =
      Uri(scheme: 'https', host: 'www.meti.go.jp', path: fulCsvPath);
  client = HttpClient();
  try {
    HttpClientRequest request = await client.getUrl(fulCsvUri);
    HttpClientResponse response = await request.close();
    var outSink = File(fulXlsx).openWrite();
    await for (var chank in response) {
      outSink.add(chank);
    }
    await outSink.close();
  } finally {
    client.close();
  }
}

Future<void> extFul() async {
  Process.runSync('libreoffice', [
    '--headless',
    '--convert-to',
    'csv:Text - txt - csv (StarCalc):44,34,76,,,,,,true',
    fulXlsx,
    '--outdir',
    pls
  ]);
  var ix = 0;
  await for (var l in readCsvLines(fulCsv).skip(1)) {
    ix++;
    var id = 'EUL$ix';
    var listCode = 'EUL';
    var row = <String, String>{
      'source': 'Foreigh End User List (EUL) '
          '- Ministry of Economy, Trade and Industry, Japan',
      'No.': l[0]!,
      'Country or Region': l[1]!,
      'Company or Organization': l[2]!,
      if (l[3] != null) 'Also Known As': l[3]!,
      'Type of WMD': l[4]!,
    };
    var rowJson = <String, dynamic>{'id': id, 'body': row};
    var rowJsonString = jsonEncoderIndent.convert(rowJson);
    if (first) {
      first = false;
    } else {
      outSinkJson.writeln(',');
    }
    outSinkJson.write(rowJsonString);
    var n = l[2]!;
    n = n.replaceAll(rCrConnector, ' ');
    n = n.trim();
    n = n.replaceFirstMapped(rTrailCamma, (match) => match.group(1)!);
    outSinkCsv
      ..write(quoteCsvCell(normalize(n)))
      ..write(',')
      ..write(quoteCsvCell(id))
      ..write(',')
      ..write(quoteCsvCell(listCode))
      ..write('\r\n');
    var a = l[3];
    if (a == null) {
      continue;
    }
    var aliases = a.split(rBulletSplitter);
    for (var a in aliases) {
      a = a.replaceAll(rCrConnector, ' ');
      a = a.trim();
      a = a.replaceFirstMapped(rTrailCamma, (match) => match.group(1)!);
      a = a.replaceFirst(rBullet, '');
      a = a.replaceFirstMapped(rDoubleQuate, (match) => match.group(1)!);
      if (a == '') {
        continue;
      }
      outSinkCsv
        ..write(quoteCsvCell(normalize(a)))
        ..write(',')
        ..write(quoteCsvCell(id))
        ..write(',')
        ..write(quoteCsvCell(listCode))
        ..write('\r\n');
    }
  }
}
