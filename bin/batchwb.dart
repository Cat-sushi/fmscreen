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
import 'dart:math';

import 'package:args/args.dart';
import 'package:async/async.dart';

import 'package:fmscreen/fmscreen.dart';
import 'package:fmscreen/src/bparts.dart';
import 'package:fmscreen/src/util.dart';

late IOSink resultSink;
late IOSink logSink;
late DateTime startTime;
late DateTime currentLap;
late DateTime lastLap;

var bulkSize = 100;
var lc = 0;
var cacheHits = 0;
var cacheHits2 = 0;

void main(List<String> args) async {
  var argParser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'print tis help')
    ..addOption('bulk', abbr: 'b', valueHelp: 'bulk size of request')
    ..addOption('input', abbr: 'i', valueHelp: 'input file');
  var options = argParser.parse(args);
  if (options['help'] == true) {
    print(argParser.usage);
    exit(0);
  }

  if (options['bulk'] != null) {
    bulkSize = max(int.tryParse(options['bulk'] as String) ?? bulkSize, 1);
  }
  var queryPath = options['input'] as String? ?? 'batch/queries.csv';

  print('Starting web bulk batch: ${DateTime.now()}');
  await time(() => wbatch(queryPath), 'wbatch');
  print('Web bulk batch endded: $lc\t${DateTime.now()}');
}

Future<void> wbatch(String queryPath) async {
  if (!queryPath.endsWith('.csv')) {
    print('Invalid input file name: $queryPath');
    exit(1);
  }
  var queries = StreamQueue<String>(openQueryListStream(queryPath));
  var trank = queryPath.substring(0, queryPath.lastIndexOf('.csv'));
  var resultPath = '${trank}_results.csv';
  var logPath = '${trank}_log.txt';
  var resultFile = File(resultPath);
  resultSink = resultFile.openWrite()..add(utf8Bom);
  logSink = File(logPath).openWrite();
  startTime = DateTime.now();
  lastLap = startTime;
  currentLap = lastLap;
  var httpClient = HttpClient();

  while (await queries.hasNext) {
    var bulk = jsonEncode(await queries.take(bulkSize));
    var request = await httpClient.post('localhost', 8080, '');
    request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    request.write(bulk);
    var response = await request.close();
    var jsonString = await response.transform(utf8.decoder).join();
    var jsons = (jsonDecode(jsonString) as List);
    var results = jsons
        .map<ScreeningResult>(
            (dynamic e) => ScreeningResult.fromJson(e as Map<String, dynamic>))
        .toList();
    outputResults(results);
  }
  httpClient.close();
  await logSink.close();
  await resultSink.close();
}

void outputResults(Iterable<ScreeningResult> results) {
  for (var result in results) {
    ++lc;
    if (result.queryStatus.terms.isEmpty) {
      logSink.writeln(result.queryStatus.message);
      continue;
    }
    if (result.queryStatus.message != '') {
      cacheHits++;
      cacheHits2++;
    }
    resultSink.write(formatOutput(lc, result));
    if ((lc % bulkSize) == 0) {
      currentLap = DateTime.now();
      print('$lc\t${currentLap.difference(startTime).inMilliseconds}'
          '\t${currentLap.difference(lastLap).inMilliseconds}'
          '\t\t$cacheHits2\t$cacheHits');
      cacheHits2 = 0;
      lastLap = currentLap;
    }
  }
}
