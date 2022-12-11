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

/// Internal ID of a item of the denial lists.
///
/// This is concatanated with the DB version.
class ItemId {
  static final _canonicalized = <String, ItemId>{};
  final String id;
  static const dummy = ItemId._('');

  const ItemId._(this.id);
  factory ItemId._fromExternalId(String eid) {
    var id = '${eid}_$_databaseVersion';
    var ret = _canonicalized[id];
    if (ret != null) {
      return ret;
    }
    return _canonicalized[id] = ItemId._(id);
  }
  int get length => id.length;
  String toJson() => id;
  @override
  int get hashCode => id.hashCode;
  @override
  operator ==(Object other) => id == (other as ItemId).id;
}

/// A detected item of the denial lists.
class DetectedItem implements Comparable {
  /// The internal item ID.
  final ItemId itemId;

  /// Matched names with score.
  ///
  /// sorted by score
  final List<MatchedEntry> matchedNames;

  /// Code of denial list
  final String listCode;

  /// The body of the detected item in JSON
  final Map<String, dynamic>? body;

  DetectedItem(this.itemId, this.matchedNames, this.listCode, this.body);

  @override
  int compareTo(dynamic other) {
    var r = -matchedNames[0].score.compareTo(other.matchedNames[0].score);
    if (r != 0) {
      return r;
    }
    r = matchedNames[0]
        .entry
        .length
        .compareTo(other.matchedNames[0].entry.length);
    if (r != 0) {
      return r;
    }
    return matchedNames[0].entry.compareTo(other.matchedNames[0].entry);
  }

  DetectedItem.fromJson(dynamic json)
      : itemId = ItemId._(json['itemId']),
        matchedNames = json['matchedNames']
            .map<MatchedEntry>((e) => MatchedEntry.fromJson(e))
            .toList(),
        listCode = json['listCode'],
        body = json['body'];

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'itemId': itemId,
      'matchedNames': matchedNames.map((e) => e.toJson()).toList(),
      'listCode': listCode,
      if (body != null) 'body': body
    };
  }
}

/// Status of the query for screening.
class QueryStatus {
  /// The ID of the sever `Isolate` used for fuzzy matching.
  final int serverId;

  /// The [DateTime] of starting fuzzy matching.
  final DateTime start;

  /// The duration in milli seconds of fuzzy matching.
  final int durationInMilliseconds;
  final String inputString;

  /// The normalized name for screening.
  final String rawQuery;

  /// Legal entity type position, Postfix/ prefix/ none
  final LetType letType;

  /// The terms of the preprocessd name.
  final List<Term> terms;

  /// True, if the query is specified for perfect matching.
  final bool perfectMatching;

  /// The discernment of the query.
  final double queryScore;

  /// True, if the query terms are reduced for perfomance reasons.
  final bool queryFallenBack;

  /// The [DateTime] when the database created.
  final String databaseVersion;

  /// The message from the fuzzy matcher.
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
        databaseVersion = DateTime.fromMillisecondsSinceEpoch(_databaseVersion)
            .toUtc()
            .toIso8601String(),
        message = result.message;
  QueryStatus.fromJson(Map<String, dynamic> json)
      : serverId = json['serverId'],
        start = DateTime.parse(json['start']),
        durationInMilliseconds = json['durationInMilliseconds'],
        inputString = json['inputString'],
        rawQuery = json['rawQuery'],
        letType = LetType.fromJson(json['letType']),
        terms = json['terms'].map<Term>((e) => Term(e)).toList(),
        perfectMatching = json['perfectMatching'],
        queryScore = json['queryScore'],
        queryFallenBack = json['queryFallenBack'],
        databaseVersion = json['databaseVersion'],
        message = json['message'];
  QueryStatus.fromError(String errorMessage)
      : serverId = 0,
        start = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        durationInMilliseconds = 0,
        inputString = '',
        rawQuery = '',
        letType = LetType.none,
        terms = [],
        perfectMatching = false,
        queryScore = 0.0,
        queryFallenBack = false,
        databaseVersion = '00000000T000000Z',
        message = errorMessage;
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
      'databaseVersion': databaseVersion,
      'message': message
    };
  }
}

/// A result of screening
class ScreeningResult {
  final QueryStatus queryStatus;
  final List<DetectedItem> detectedItems;
  ScreeningResult(this.queryStatus, this.detectedItems);
  ScreeningResult.fromJson(dynamic json)
      : queryStatus = QueryStatus.fromJson(json['queryStatus']),
        detectedItems = json['detectedItems']
            .map<DetectedItem>((e) => DetectedItem.fromJson(e))
            .toList();
  ScreeningResult.fromError(String errorMessage)
      : queryStatus = QueryStatus.fromError(errorMessage),
      detectedItems = [];
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'queryStatus': queryStatus,
      'detectedItems': detectedItems.map((e) => e.toJson()).toList()
    };
  }
}
