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

part of fmscreen;

// This is concatanated with the hashCode of DB version and it self.
class ItemId {
  static final _canonicalized = <String, ItemId>{};
  final String id;
  static const dummy = ItemId._('');

  const ItemId._(this.id);
  factory ItemId._canonicalize(String id) {
    var ret = _canonicalized[id];
    if (ret != null) {
      return ret;
    }
    return _canonicalized[id] = ItemId._(id);
  }
  factory ItemId._fromExternalId(String id) {
    var id2 = '$id\$${Object.hashAll([id, _databaseVersion])}';
    return ItemId._canonicalize(id2);
  }
  int get length => id.length;
  String toJson() => id;
  @override
  int get hashCode => id.hashCode;
  @override
  operator ==(Object other) => id == (other as ItemId).id;
}

typedef ItemData = Map<String, dynamic>;

/// Query matched Denial List.
class DetectedItem implements Comparable {
  late final ItemId itemId;

  /// sorted by score
  final List<MatchedEntry> matchedEntries;

  final Map<String, dynamic>? data;

  DetectedItem(this.itemId, this.matchedEntries, this.data);

  @override
  int compareTo(dynamic other) {
    var r = -matchedEntries[0].score.compareTo(other.matchedEntries[0].score);
    if (r != 0) {
      return r;
    }
    r = matchedEntries[0]
        .entry
        .length
        .compareTo(other.matchedEntries[0].entry.length);
    if (r != 0) {
      return r;
    }
    return matchedEntries[0].entry.compareTo(other.matchedEntries[0].entry);
  }

  DetectedItem.fromJson(dynamic json)
      : itemId = ItemId._canonicalize(json['itemId']),
        matchedEntries = json['matchedEntries']
            .map<MatchedEntry>((e) => MatchedEntry.fromJson(e))
            .toList(),
        data = json['data'];

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'itemId': itemId,
      'matchedEntries': matchedEntries.map((e) => e.toJson()).toList(),
      if (data != null) 'data': data
    };
  }
}

class QueryStatus {
  final int serverId;
  final DateTime start;
  final int durationInMilliseconds;
  final String inputString;
  final String rawQuery;
  final LetType letType;
  final List<Term> terms;
  final bool perfectMatching;
  final double queryScore;
  final bool queryFallenBack;
  final String message;
  QueryStatus.fromQueryResult(QueryResult result)
      : serverId = result.serverId,
        start = result.dateTime,
        durationInMilliseconds = result.durationInMilliseconds,
        inputString = result.inputString,
        rawQuery = result.rawQuery,
        letType = result.cachedResult.cachedQuery.letType,
        terms = result.cachedResult.cachedQuery.terms,
        perfectMatching = result.cachedResult.cachedQuery.perfectMatching,
        queryScore = result.cachedResult.queryScore,
        queryFallenBack = result.cachedResult.queryFallenBack,
        message = result.message;
  QueryStatus.fromJson(Map<String, dynamic> json)
      : serverId = json['serverId'],
        start = DateTime.parse(json['start']),
        durationInMilliseconds = json['durationInMilliseconds'],
        inputString = json['inputString'],
        rawQuery = json['rawQuery'],
        letType = LetType.fromJson(json['letType']),
        terms = json['terms'].map<Term>((e) => Term(e)).toList(),
        perfectMatching = json['perfectMatching'] == 'true' ? true : false,
        queryScore = json['queryScore'],
        queryFallenBack = json['queryFallenBack'] == 'true' ? true : false,
        message = json['message'];
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'serverId': serverId,
      'start': start.toUtc().toIso8601String(),
      'durationInMilliseconds': durationInMilliseconds,
      'inputString': inputString,
      'rawQuery': rawQuery,
      'letType': letType,
      'terms': terms.map((e) => e.toJson()).toList(),
      'perfectMatching': perfectMatching,
      'queryScore': queryScore,
      'queryFallenBack': queryFallenBack,
      'message': message
    };
  }
}

class ScreeningResult {
  final QueryStatus queryStatus;
  final List<DetectedItem> detectedItems;
  ScreeningResult(this.queryStatus, this.detectedItems);
  ScreeningResult.fromJson(dynamic json)
      : queryStatus = QueryStatus.fromJson(json['queryStatus']),
        detectedItems = json['detectedItems']
            .map<DetectedItem>((e) => DetectedItem.fromJson(e))
            .toList();
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'queryStatus': queryStatus,
      'detectedItems': detectedItems.map((e) => e.toJson()).toList()
    };
  }
}
