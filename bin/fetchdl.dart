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

import 'package:async/async.dart';
import 'package:excel/excel.dart';
import 'package:fmatch/fmatch.dart';
import 'package:fmscreen/src/util.dart';
import 'package:html/parser.dart';

final databaseDirectoryPath = 'assets/database';

// https://www.trade.gov/consolidated-screening-list JSON
final consolidatedUri = Uri(
    scheme: 'https',
    host: 'data.trade.gov',
    path: '/downloadable_consolidated_screening_list/v1/consolidated.json');
final consolidatedJsonPath = '$databaseDirectoryPath/consolidated.json';
final consolidatedJsonIndentPath =
    '$databaseDirectoryPath/consolidated_indent.json';

final fulUri = Uri(
    scheme: 'https', host: 'www.meti.go.jp', path: '/policy/anpo/law05.html');
final fulHtmlPath = '$databaseDirectoryPath/ful.html';
final fulXlsxPath = '$databaseDirectoryPath/ful.xlsx';
final fulCsvPath = '$databaseDirectoryPath/ful.csv';
final dbPath = '$databaseDirectoryPath/db.csv';
final idbPath = '$databaseDirectoryPath/idb.json';

final listCsvPath = '$databaseDirectoryPath/list.csv';
late final IOSink listCsvOutSink;
final id2BodyJsonPath = '$databaseDirectoryPath/id2body.json';
late final IOSink id2BodyJsonOutSink;
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
  Directory.current = File.fromUri(Platform.script).parent;
  Directory.current = '..';

  final consolidatedJsonFile = File(consolidatedJsonPath);
  final fetching = !consolidatedJsonFile.existsSync() ||
      DateTime.now()
              .difference(consolidatedJsonFile.lastModifiedSync())
              .inHours >=
          5;

  var start = DateTime.now();
  var end = start;
  if (fetching) {
    print("Fetching consolidated list.");
    await fetchConsolidatedJson();
    end = DateTime.now();
    print(end.difference(start).inMilliseconds);

    start = end;
    print("Fetching foreign user list.");
    await fetchFulExlsx();
    end = DateTime.now();
    print(end.difference(start).inMilliseconds);
  }

  listCsvOutSink = File('$listCsvPath.new').openWrite()..add(utf8Bom);
  id2BodyJsonOutSink = File('$id2BodyJsonPath.new').openWrite()..writeln('[');

  print("Extracting entries from consolidated list.");
  start = end;
  await extractFromConsolidatedJson();
  await listCsvOutSink.flush();
  await id2BodyJsonOutSink.flush();
  end = DateTime.now();
  print(end.difference(start).inMilliseconds);

  start = end;
  print("Extracting entries from foreign user list.");
  await extractFromFulExlsx();
  end = DateTime.now();
  print(end.difference(start).inMilliseconds);

  await listCsvOutSink.close();
  id2BodyJsonOutSink.write('\n]');
  await id2BodyJsonOutSink.close();

  if (await fileDiff(listCsvPath, '$listCsvPath.new') ||
      await fileDiff(id2BodyJsonPath, '$id2BodyJsonPath.new')) {
    try {
      File(listCsvPath).deleteSync();
    } catch (e) {
      // do nothing
    }
    try {
      File(id2BodyJsonPath).deleteSync();
    } catch (e) {
      // do nothing
    }
    File('$listCsvPath.new').renameSync(listCsvPath);
    File('$id2BodyJsonPath.new').renameSync(id2BodyJsonPath);
  } else {
    File('$listCsvPath.new').deleteSync();
    File('$id2BodyJsonPath.new').deleteSync();
  }

  try {
    File(dbPath).renameSync('$dbPath.old');
  } catch (e) {
    // do nothing;
  }
  try {
    File(idbPath).renameSync('$idbPath.old');
  } catch (e) {
    // do nothing;
  }
  print("Building db and idb.");
  final matcher = FMatcher();
  await matcher.init();
  if (!await fileDiff(dbPath, '$dbPath.old') &&
      !await fileDiff(idbPath, '$idbPath.old')) {
    try {
      await File('$dbPath.old').delete();
    } catch (e) {
      // do nothing;
    }
    try {
      await File('$idbPath.old').delete();
    } catch (e) {
      // do nothing;
    }
    print('db and idb are not updated.');
    exit(1);
  }
  try {
    await File('$dbPath.old').delete();
  } catch (e) {
    // do nothing
  }
  try {
    await File('$idbPath.old').delete();
  } catch (e) {
    // do nothing
  }
  print('db and/or idb are updated.');
}

Future<bool> fileDiff(String path1, String path2) async {
  final file1 = File(path1);
  final file2 = File(path2);
  if (!file1.existsSync() || !file2.existsSync()) {
    return true;
  }
  final Stream<List<int>> stream1;
  try {
    stream1 = file1.openRead();
  } catch (e) {
    return true;
  }
  var lineStream1 =
      stream1.transform(utf8.decoder).transform(const LineSplitter());
  final Stream<List<int>> stream2;
  try {
    stream2 = file2.openRead();
  } catch (e) {
    return true;
  }
  var lineStream2 = stream2
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream(
          onListen: (s) => s.resume(), onCancel: (s) => s.pause());
  await for (final line1 in lineStream1) {
    String line2;
    try {
      line2 = await lineStream2.first;
    } catch (e) {
      return true;
    }
    if (line1 != line2) {
      return true;
    }
  }
  if (await lineStream2.firstOrNull != null) {
    return true;
  }
  return false;
}

Future<void> fetchConsolidatedJson() async {
  var client = HttpClient();
  try {
    HttpClientRequest request = await client.getUrl(consolidatedUri);
    HttpClientResponse response = await request.close();
    var outSink = File(consolidatedJsonPath).openWrite();
    await for (var chank in response) {
      outSink.add(chank);
    }
    await outSink.close();
  } finally {
    client.close();
  }
}

final regExpSource = RegExp(r'^.*\(([^)]+)\).*');

Future<void> extractFromConsolidatedJson() async {
  final jsonString = File(consolidatedJsonPath).readAsStringSync();
  final jsonObject = jsonDecode(jsonString) as Map<String, dynamic>;
  final jsonStringIndent = jsonEncoderIndent.convert(jsonObject);
  final outSinkIndent = File(consolidatedJsonIndentPath).openWrite();
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
      id2BodyJsonOutSink.writeln(',');
    }
    id2BodyJsonOutSink.write(rowJsonString);
    if (row['name'] != null) {
      var name = row['name'] as String;
      name = name.replaceAll(rNewLine, ' ');
      listCsvOutSink
        ..write(quoteCsvCell(normalize(name)))
        ..write(',')
        ..write(quoteCsvCell(id))
        ..write(',')
        ..write(quoteCsvCell(listCode))
        ..write('\r\n');
    }
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
        listCsvOutSink
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
        ret[e.key as String] = r;
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

Future<void> fetchFulExlsx() async {
  var client = HttpClient();
  String stringData;
  try {
    HttpClientRequest request = await client.getUrl(fulUri);
    HttpClientResponse response = await request.close();
    stringData = await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
  var htmlSink = File(fulHtmlPath).openWrite();
  htmlSink.write(stringData);
  await htmlSink.close();
  var fulHtmlSring = File(fulHtmlPath).readAsStringSync();
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
    var outSink = File(fulXlsxPath).openWrite();
    await for (var chank in response) {
      outSink.add(chank);
    }
    await outSink.close();
  } finally {
    client.close();
  }
}

final doubleQuateRegExp = RegExp('"', multiLine: true, unicode: true);
Future<void> extractFromFulExlsx() async {
  var outSinkFulCsv = File(fulCsvPath).openWrite();
  var excel = Excel.decodeBytes(File(fulXlsxPath).readAsBytesSync());
  var rowIndex = 0;
  for (final row in excel.sheets.values.first.rows) {
    if (row[0]?.value == null) {
      break;
    }
    var columnIndex = 0;
    for (final column in row) {
      if (columnIndex == 0) {
        if (rowIndex == 0) {
          outSinkFulCsv.write('${column?.value ?? ''}');
        } else {
          outSinkFulCsv.write('$rowIndex');
        }
      } else {
        var columnValue = column?.value;
        if (columnValue == null) {
          outSinkFulCsv.write(',');
        } else {
          var columnString = columnValue.toString().replaceAll(doubleQuateRegExp, '""');
          outSinkFulCsv.write(',"$columnString"');
        }
      }
      columnIndex++;
    }
    outSinkFulCsv.write('\n');
    rowIndex++;
  }
  await outSinkFulCsv.flush();
  await outSinkFulCsv.close();
  var ix = 0;
  await for (var l in readCsvLines(fulCsvPath).skip(1)) {
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
      id2BodyJsonOutSink.writeln(',');
    }
    id2BodyJsonOutSink.write(rowJsonString);
    var n = l[2]!;
    n = n.replaceAll(rCrConnector, ' ');
    n = n.trim();
    n = n.replaceFirstMapped(rTrailCamma, (match) => match.group(1)!);
    listCsvOutSink
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
      listCsvOutSink
        ..write(quoteCsvCell(normalize(a)))
        ..write(',')
        ..write(quoteCsvCell(id))
        ..write(',')
        ..write(quoteCsvCell(listCode))
        ..write('\r\n');
    }
  }
}
