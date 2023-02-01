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

/// A screening server for entity/ person name against denial lists such as BIS Entity List.
library fmscreen;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fmatch/fmatch.dart';
export 'package:fmatch/fmatch.dart'
    show normalize, LetType, Term, Entry, MatchedEntry;
import 'package:simple_mutex/simple_mutex.dart';

import 'src/util.dart';

part 'fmsclasses.dart';

int _databaseVersion = 0;

/// The screening engine.
class Screener {
  /// If youu will [stopServers] asynchronously, pass [mutex] `true`.
  Screener({bool mutex = false, int cacheSize = 10000})
      : _mutex = mutex ? Mutex() : null,
        _cacheSize = cacheSize;

  final Mutex? _mutex;
  final int _cacheSize;
  final _entry2ItemIds = <Entry, List<ItemId>>{};
  final _itemId2ListCode = <ItemId, String>{};
  final _itemId2Body = <ItemId, Map<String, dynamic>>{};
  late final FMatcherP _fmatcherp;
  var _started = false;
  var _stopped = false;

  Future<void> _readList(String path) async {
    await for (var l in readCsvLines(path)) {
      if (l.length < 3) {
        continue;
      }
      var name = l[0];
      var externItemId = l[1];
      var listCode = l[2];
      if (name == null || externItemId == null || listCode == null) {
        continue;
      }
      var entry = Entry(name);
      if (_entry2ItemIds[entry] == null) {
        _entry2ItemIds[entry] = [];
      }
      var itemID = ItemId._fromExternalId(externItemId);
      _entry2ItemIds[entry]!.add(itemID);
      _itemId2ListCode[itemID] = listCode;
    }
  }

  void _readItemId2Body(String path) {
    var jsonString = File(path).readAsStringSync();
    var json = jsonDecode(jsonString) as List<dynamic>;
    for (var e in json) {
      var eid = (e as Map<String, dynamic>)['id']! as String;
      var body = e['body']! as Map<String, dynamic>;
      _itemId2Body[ItemId._fromExternalId(eid)] = body;
    }
  }

  /// Initialize this screener.
  ///
  /// Call and `await` this before use this screener.
  Future<void> init() async {
    if (_started) {
      throw 'Bad Status';
    }
    var fmatcher = FMatcher();
    await fmatcher.init();
    fmatcher.queryResultCacheSize = _cacheSize;
    _fmatcherp = FMatcherP.fromFMatcher(fmatcher);
    await _fmatcherp.startServers();
    _databaseVersion = _fmatcherp.fmatcher.databaseVersion;
    await _readList('assets/database/list.csv');
    _readItemId2Body('assets/database/id2body.json');
    _started = true;
  }

  /// This stops the internal server `Isolate`s.
  void stopServers() {
    if (_stopped) {
      throw 'Bad Status';
    }
    if (_mutex == null) {
      _fmatcherp.stopServers(); // unawaited
      return;
    }
    _mutex!.critical(_fmatcherp.stopServers); // unawaited
    _stopped = true;
  }

  /// Do screening.
  ///
  /// If you need item body, pass [verbose] `true`.
  ///
  /// If you temporarily want to disable result cache, pass [cache] `false`.
  ///
  /// This is reentrant and works parallelly with `Isolate`s.
  Future<ScreeningResult> screen(String query,
      {bool cache = true, bool verbose = false}) async {
    if (!_started || _stopped) {
      throw 'Bad Status';
    }
    var queryResults = _mutex == null
        ? await _fmatcherp.fmatch(query, cache)
        : await _mutex!.criticalShared(() => _fmatcherp.fmatch(query, cache));
    var screeningResult = _detectItems(queryResults, verbose);
    return screeningResult;
  }

  /// Do screening of multiple names, parallelly.
  ///
  /// If you need item body, pass [verbose] `true`.
  ///
  /// If you temporarily want to disable result cache, pass [cache] `false`.
  Future<List<ScreeningResult>> screenb(List<String> queries,
      {bool cache = true, bool verbose = false}) async {
    if (!_started || _stopped) {
      throw 'Bad Status';
    }
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
      var listCode = _itemId2ListCode[e.key]!;
      Map<String, dynamic>? body;
      if (verbose) {
        body = _itemId2Body[e.key];
      }
      var detectedItem = DetectedItem(e.key, e.value, listCode, body);
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
