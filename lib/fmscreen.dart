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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fmatch/fmatch.dart';

import 'src/util.dart';

part 'fmsclasses.dart';

int _databaseVersion = 0;

class _Entry2ItemIds {
  final _map = <Entry, List<ItemId>>{};
  Future<void> readCsv(String path) async {
    await for (var l in readCsvLines(path)) {
      if (l.length < 2) {
        continue;
      }
      var name = l[0];
      var itemId = l[1];
      if (name == null || itemId == null) {
        continue;
      }
      var entry = Entry(name);
      if (_map[entry] == null) {
        _map[entry] = [];
      }
      _map[entry]!.add(ItemId._fromExternalId(itemId));
    }
  }

  List<ItemId>? operator [](Entry entry) => _map[entry];
  operator []=(Entry entry, List<ItemId> ids) => _map[entry] = ids;
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
  final _entry2ItemIds = _Entry2ItemIds();
  final _itemId2Data = _Item2Data();
  late final FMatcher _fmatcher;
  late final FMatcherP _fmatcherp;

  Future<void> init() async {
    _fmatcher = FMatcher();
    await _fmatcher.init();
    _databaseVersion = _fmatcher.databaseVersion;
    _fmatcherp = FMatcherP.fromFMatcher(_fmatcher);
    await _fmatcherp.startServers();
    await _entry2ItemIds.readCsv('database/list.csv');
    _itemId2Data.readJson('database/id2data.json');
  }

  /// This stops the internal servers for restarting internal servers.
  ///
  /// Usage
  ///
  /// Declearation.
  /// ```dart
  /// late Screener screener;
  /// final mutex = Mutex();
  /// ```
  /// Initialization. (starting the internal servers.)
  /// ```dart
  /// screener = Screener();
  /// await screener.init();
  /// ```
  /// Restarting the internal servers.
  /// ```dart
  /// await mutex.lock();
  /// screener.stopServers();
  /// screener = Screener();
  /// await screener.init();
  /// mutex.unlock();
  /// ```
  /// Screening. (Asynchronous, Bulk)
  /// ```dart
  /// await mutex.lockShared();
  /// result = screener.screenb(['abc', 'def']);
  /// mutex.unlockShared();
  /// ```
  Future<void> stopServers() {
    return _fmatcherp.stopServers();
  }

  Future<ScreeningResult> screen(String query,
      {bool cache = true, bool verbose = false}) async {
    var queryResults = await _fmatcherp.fmatch(query, cache);
    var screeningResult = _detectItems(queryResults, verbose);
    return screeningResult;
  }

  Future<List<ScreeningResult>> screenb(List<String> queries,
      {bool cache = true, bool verbose = false}) async {
    var queryResults = await _fmatcherp.fmatchb(queries, cache);
    var screeningResults = <ScreeningResult>[];
    for (var queryResult in queryResults) {
      screeningResults.add(_detectItems(queryResult, verbose));
    }
    return screeningResults;
  }

  ScreeningResult _detectItems(QueryResult queryResult, bool verbose) {
    var itemId2Entries = <ItemId, List<MatchedEntry>>{};
    for (var matchedEntry in queryResult.cachedResult.matchedEntiries) {
      var itemIds = _entry2ItemIds[matchedEntry.entry]!;
      for (var itemId in itemIds) {
        if (itemId2Entries[itemId] == null) {
          itemId2Entries[itemId] = [];
        }
        itemId2Entries[itemId]!.add(matchedEntry);
      }
    }
    var detectedItems = <DetectedItem>[];
    for (var e in itemId2Entries.entries) {
      dynamic data;
      if (verbose) {
        data = _itemId2Data[e.key];
      }
      var detectedItem = DetectedItem(e.key, e.value, data);
      detectedItems.add(detectedItem);
    }
    detectedItems.sort();
    var queryStatus = QueryStatus.fromQueryResult(queryResult);
    var ret = ScreeningResult(queryStatus, detectedItems);
    return ret;
  }

  ItemData? itemData(String itemId) {
    return _itemId2Data[ItemId._canonicalize(itemId)];
  }
}
