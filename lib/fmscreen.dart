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
import 'package:simple_mutex/simple_mutex.dart';

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
      var externItemId = l[1];
      if (name == null || externItemId == null) {
        continue;
      }
      var entry = Entry(name);
      if (_map[entry] == null) {
        _map[entry] = [];
      }
      _map[entry]!.add(ItemId._fromExternalId(externItemId));
    }
  }

  List<ItemId>? operator [](Entry entry) => _map[entry];
  operator []=(Entry entry, List<ItemId> ids) => _map[entry] = ids;
}

class _Item2Body {
  final _map = <ItemId, Map<String, dynamic>>{};

  void readJson(String path) {
    var jsonString = File(path).readAsStringSync();
    var json = jsonDecode(jsonString) as List<dynamic>;
    for (var e in json) {
      var eid = (e as Map<String, dynamic>)['id']! as String;
      var body = e['body']! as Map<String, dynamic>;
      _map[ItemId._fromExternalId(eid)] = body;
    }
  }

  Map<String, dynamic>? operator [](ItemId id) => _map[id];
  operator []=(ItemId id, Map<String, dynamic> body) => _map[id] = body;
}

/// The screening engine.
class Screener {
  /// If youu will [stopServers] asynchronously, pass [mutex] `true`.
  Screener([bool mutex = false]) : _mutex = mutex ? Mutex() : null;

  final Mutex? _mutex;
  final _entry2ItemIds = _Entry2ItemIds();
  final _itemId2Body = _Item2Body();
  late final FMatcher _fmatcher;
  late final FMatcherP _fmatcherp;

  /// Initialize this screener.
  ///
  /// Call and `await` this before use this screener.
  Future<void> init() async {
    _fmatcher = FMatcher();
    await _fmatcher.init();
    _databaseVersion = _fmatcher.databaseVersion;
    _fmatcherp = FMatcherP.fromFMatcher(_fmatcher);
    await _fmatcherp.startServers();
    await _entry2ItemIds.readCsv('database/list.csv');
    _itemId2Body.readJson('database/id2body.json');
  }

  /// This stops the internal server `Isolate`s.
  void stopServers() {
    if (_mutex == null) {
      _fmatcherp.stopServers(); // unawaited
      return;
    }
    _mutex!.critical(_fmatcherp.stopServers); // unawaited
  }

  /// Do screening.
  ///
  /// If you need item body, pass [verbose] `true`.
  ///
  /// If you temporarily want to disable result cache, pass [cache] `false`.
  Future<ScreeningResult> screen(String query,
      {bool cache = true, bool verbose = false}) async {
    var queryResults = _mutex == null
        ? await _fmatcherp.fmatch(query, cache)
        : await _mutex!.criticalShared(() => _fmatcherp.fmatch(query, cache));
    var screeningResult = _detectItems(queryResults, verbose);
    return screeningResult;
  }

  /// Do screening of multiple names.
  ///
  /// If you need item body, pass [verbose] `true`.
  ///
  /// If you temporarily want to disable result cache, pass [cache] `false`.
  Future<List<ScreeningResult>> screenb(List<String> queries,
      {bool cache = true, bool verbose = false}) async {
    var queryResults = _mutex == null
        ? await _fmatcherp.fmatchb(queries, cache)
        : await _mutex!
            .criticalShared(() => _fmatcherp.fmatchb(queries, cache));
    var screeningResults = List.generate(
        queryResults.length, (i) => _detectItems(queryResults[i], verbose));
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
      dynamic body;
      if (verbose) {
        body = _itemId2Body[e.key];
      }
      var detectedItem = DetectedItem(e.key, e.value, body);
      detectedItems.add(detectedItem);
    }
    detectedItems.sort();
    var queryStatus = QueryStatus.fromQueryResult(queryResult);
    var ret = ScreeningResult(queryStatus, detectedItems);
    return ret;
  }

  /// Get the body of the itemId which is string representation of [ItemId].
  Map<String, dynamic>? itemBody(String itemId) {
    return _itemId2Body[ItemId._(itemId)];
  }
}
