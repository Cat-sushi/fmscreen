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

import 'package:fmatch/fmatch.dart';

import '../fmscreen.dart';
import 'util.dart';

Stream<String> openQueryListStream(String batchQueryPath) async* {
  await for (var line in readCsvLines(batchQueryPath)) {
    if (line.isEmpty) {
      continue;
    }
    var query = line[0];
    if (query == null || query == '') {
      continue;
    }
    yield query;
  }
}

String formatOutput(int ix, ScreeningResult result) {
  var csvLine = StringBuffer();
  if (result.detectedItems.isEmpty) {
    result.detectedItems
        .add(DetectedItem(ItemId.dummy, [MatchedEntry(Entry(''), 0.0)], null));
  }
  for (var e in result.detectedItems) {
    csvLine.write(result.queryStatus.serverId);
    csvLine.write(r',');
    csvLine.write(
        (result.queryStatus.durationInMilliseconds.toDouble() / 1000.0)
            .toStringAsFixed(3));
    csvLine.write(r',');
    csvLine.write(ix);
    csvLine.write(r',');
    if (result.queryStatus.queryScore == 0) {
      csvLine.write('0.00');
    } else {
      csvLine.write((e.matchedNames[0].score / result.queryStatus.queryScore)
          .toStringAsFixed(2));
    }
    csvLine.write(r',');
    csvLine.write(result.queryStatus.queryScore.toStringAsFixed(2));
    csvLine.write(r',');
    if (result.detectedItems[0].matchedNames[0].entry.string == '') {
      csvLine.write('0');
    } else {
      csvLine.write(result.detectedItems.length);
    }
    csvLine.write(r',');
    csvLine.write(quoteCsvCell(result.queryStatus.rawQuery));
    csvLine.write(r',');
    csvLine.write(quoteCsvCell(e.matchedNames[0].entry.string));
    csvLine.write(r',');
    csvLine.write(result.queryStatus.letType.name);
    for (var e in result.queryStatus.terms) {
      csvLine.write(r',');
      csvLine.write(quoteCsvCell(e.string));
    }
    csvLine.write('\r\n');
  }
  return csvLine.toString();
}
