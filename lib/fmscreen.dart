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

library fmscreen;

import 'dart:convert';
import 'dart:io';

import 'package:fmatch/fmatch.dart';

import 'src/util.dart';

part 'fmsclasses.dart';

int _databaseVersion = 0;

class _Entry2ItemId {
  final _map = <Entry, ItemId>{};
  Future<void> readCsv(String path) async {
    await for (var l in readCsvLines(path)) {
      if (l.length < 2 || l[0] == null || l[1] == null) {
        continue;
      }
      _map[Entry(l[0]!)] = ItemId._fromExternalId(l[1]!);
    }
  }

  ItemId? operator [](Entry entry) => _map[entry];
  operator []=(Entry entry, ItemId id) => _map[entry] = id;
}

class _Item2Data {
  final _map = <ItemId, ItemData>{};
  void readJson(String path) {
    var jsonString = File(path).readAsStringSync();
    var json = jsonDecode(jsonString) as List<dynamic>;
    for (var e in json) {
      var id = (e as Map<String, dynamic>)['id']! as String;
      var data = e['data']! as Map<String, dynamic>;
      _map[ItemId._fromExternalId(id)] = data;
    }
  }

  ItemData? operator [](ItemId id) => _map[id];
  operator []=(ItemId id, Map<String, dynamic> data) => _map[id] = data;
}

class Screener {
  final _entry2ItemId = _Entry2ItemId();
  final _itemId2Data = _Item2Data();
  late final FMatcher _fmatcher;
  late final FMatcherP _fmatcherp;

  Future<void> init() async {
    _fmatcher = FMatcher();
    await _fmatcher.init();
    _fmatcherp = FMatcherP.fromFMatcher(_fmatcher);
    await _fmatcherp.startServers();
    await _entry2ItemId.readCsv('database/list.csv');
    _itemId2Data.readJson('database/id2data.json');
  }

  Future<void> stopServers() async {
    await _fmatcherp.stopServers();
  }

  Future<ScreeningResult> screen(String query,
      {bool cache = true, bool verbose = false}) async {
    var queryResults = await _fmatcherp.fmatch(query, cache);
    var screeningResult = _detectItem(queryResults, verbose);
    return screeningResult;
  }

  Future<List<ScreeningResult>> screenb(List<String> queries,
      {bool cache = true, bool verbose = false}) async {
    var queryResults = await _fmatcherp.fmatchb(queries, cache);
    var screeningResults = <ScreeningResult>[];
    for (var queryResult in queryResults) {
      screeningResults.add(_detectItem(queryResult, verbose));
    }
    return screeningResults;
  }

  ScreeningResult _detectItem(QueryResult queryResult, bool verbose) {
    var dlItemIdMap = <ItemId, List<MatchedEntry>>{};
    for (var matchedEntry in queryResult.cachedResult.matchedEntiries) {
      var dlItemId = _entry2ItemId[matchedEntry.entry]!;
      if (dlItemIdMap[dlItemId] == null) {
        dlItemIdMap[dlItemId] = [];
      }
      dlItemIdMap[dlItemId]!.add(matchedEntry);
    }
    var matchedDlItemIds = <DetectedItem>[];
    for (var e in dlItemIdMap.entries) {
      dynamic data;
      if (verbose) {
        data = _itemId2Data[e.key];
      }
      var detctedItem = DetectedItem(e.key, e.value, data);
      matchedDlItemIds.add(detctedItem);
    }
    matchedDlItemIds.sort();
    var queryProperties = QueryStatus.fromQueryResult(queryResult);
    var ret = ScreeningResult(queryProperties, matchedDlItemIds);
    return ret;
  }

  ItemData? itemData(String itemId) {
    return _itemId2Data[ItemId._canonicalize(itemId)];
  }
}
