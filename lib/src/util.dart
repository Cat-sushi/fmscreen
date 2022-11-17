// Fuzzy text matcher for entity/ persn screening.
// Copyright (c) 2020, 2022, Yako.
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

RegExp regExp(String pattern) => RegExp(pattern, unicode: true);

RegExp _escapedDoubleQuate = RegExp(r'""');
RegExp _mlDetecter = regExp(r'^(("(""|[^"])*"|[^",]+|),)*"(""|[^"])*$');
RegExp _csvParser = regExp(r'(?:"((?:""|[^"])*)"|([^",]+)|())(?:,|$)');

const utf8Bom = [0xEF, 0xBB, 0xBF];

Stream<List<String?>> readCsvLines(String filepath) async* {
  var row = '';
  var lineStream = File(filepath)
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  await for (var line in lineStream) {
    if (row != '') {
      row += '\n';
    }
    row += line;
    if (_mlDetecter.firstMatch(row) != null) {
      continue;
    }
    var ret = <String?>[];
    var start = 0;
    for (Match? m; true; start = m.end) {
      m = _csvParser.matchAsPrefix(row, start);
      if (m == null) {
        if (start != row.length) {
          print('Illegal CSV line: $row');
        }
        break;
      }
      if (m.start == m.end) {
        break;
      }
      if (m.group(1) != null) {
        ret.add(m.group(1)!.replaceAll(_escapedDoubleQuate, r'"'));
        continue;
      }
      if (m.group(2) != null) {
        ret.add(m.group(2));
        continue;
      }
      if (m.group(3) != null) {
        ret.add(null);
        continue;
      }
    }
    yield ret;
    row = '';
  }
  if (row != '') {
    print('Illegal CSV line: $row');
  }
}

String quoteCsvCell(String cell) => r'"' + cell.replaceAll(r'"', r'""') + r'"';

Future<void> time(FutureOr<void> Function() func, String name) async {
  var start = DateTime.now();
  await func();
  var end = DateTime.now();
  print('$name : ${end.difference(start).inMilliseconds}');
}

const bufferSize = 128 * 1024;

class FileChankSink implements Sink<List<int>> {
  FileChankSink.fromRaFile(this.raFile);
  final RandomAccessFile raFile;
  @override
  void add(List<int> data) {
    raFile.writeFromSync(data);
  }

  @override
  void close() {
    raFile.closeSync();
  }
}

Future<void> catFilesWithUtf8Bom(List<String> lists, String outPath) async {
  var oSink = File(outPath).openWrite()..add(utf8Bom);
  for (var list in lists) {
    var inStream = File(list).openRead();
    var first = true;
    await for (var chank in inStream) {
      if (first) {
        first = false;
        if (chank[0] == utf8Bom[0] &&
            chank[1] == utf8Bom[1] &&
            chank[2] == utf8Bom[2]) {
          chank = chank.sublist(3);
        }
      }
      oSink.add(chank);
    }
  }
  await oSink.close();
}
