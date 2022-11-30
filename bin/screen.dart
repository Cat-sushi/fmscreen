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

import 'package:args/args.dart';
import 'package:highlight/highlight.dart';
import 'package:json2yaml/json2yaml.dart';

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
    ..addFlag('cache', abbr: 'c', negatable: false, help: 'activate cache')
    ..addFlag('data',
        abbr: 'd', negatable: false, help: 'fetch data with ItemId')
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'print item data')
    ..addOption('formatter',
        abbr: 'f', defaultsTo: 'yaml', valueHelp: 'fomatter')
    ..addFlag('normalize',
        abbr: 'n', negatable: false, help: 'normalize string')
    ..addFlag('restart', negatable: false, help: 'restart server');
  ArgResults options;
  try {
    options = argParser.parse(args);
  } catch (e) {
    print(argParser.usage);
    exit(1);
  }
  if (options['help'] == true) {
    print(argParser.usage);
    exit(0);
  }

  var cache = options['cache'] as bool;
  var data = options['data'] as bool;
  var verbose = options['verbose'] as bool;
  var formtter = options['formatter'] as String;
  var normalize = options['normalize'] as bool;
  var restart = options['restart'] as bool;
  var queries = options.rest;

  var httpClient = HttpClient();

  var queryJsonString = jsonEncode(queries);

  dynamic jsonString;
  if (data) {
    if (queries.length != 1) {
      print(argParser.usage);
      exit(1);
    }
    var queryEncoded = Uri.encodeComponent(queries[0]);
    var path = '/data/$queryEncoded';
    var request = await httpClient.get('localhost', 8080, path);
    var response = await request.close();
    if (response.statusCode == 408) {
      print('Session timed out.');
      exit(1);
    }
    jsonString = await response.transform(utf8.decoder).join();
  } else if (normalize) {
    if (queries.length != 1) {
      print(argParser.usage);
      exit(1);
    }
    var queryEncoded = Uri.encodeComponent(queries[0]);
    var path = '/normalize?q=$queryEncoded';
    var request = await httpClient.get('localhost', 8080, path);
    var response = await request.close();
    jsonString = await response.transform(utf8.decoder).join();
    var normalized = jsonDecode(jsonString);
    print(normalized);
    exit(0);
  } else if (restart) {
    if (queries.isNotEmpty) {
      print(argParser.usage);
      exit(1);
    }
    var path = '/restart';
    var request = await httpClient.get('localhost', 8080, path);
    var response = await request.close();
    var responseString = await response.transform(utf8.decoder).join();
    print(responseString);
    httpClient.close();
    exit(0);
  } else if (queries.isEmpty) {
    print(argParser.usage);
    httpClient.close();
    exit(1);
  } else if (queries.length == 1) {
    var queryEncoded = Uri.encodeComponent(queries[0]);
    var path = '?c=${cache ? 1 : 0}&v=${verbose ? 1 : 0}&q=$queryEncoded';
    var request = await httpClient.get('localhost', 8080, path);
    var response = await request.close();
    jsonString = await response.transform(utf8.decoder).join();
  } else {
    var path = '?c=${cache ? 1 : 0}&v=${verbose ? 1 : 0}';
    var request = await httpClient.post('localhost', 8080, path);
    request.headers.contentType =
        ContentType('application', 'json', charset: 'utf-8');
    request.write(queryJsonString);
    var response = await request.close();
    jsonString = await response.transform(utf8.decoder).join();
  }
  httpClient.close();

  var jsonObject = jsonDecode(jsonString);

  String formatted;
  switch (formtter) {
    case 'json':
      var jsonDecoderIndent = JsonEncoder.withIndent('  ');
      formatted = jsonDecoderIndent.convert(jsonObject);
      break;
    case 'yaml':
      formatted = myJson2yaml(jsonObject);
      break;
    case 'md':
      var yaml = myJson2yaml(jsonObject);
      formatted = '```yaml\n$yaml\n```';
      break;
    case 'html':
      var yaml = myJson2yaml(jsonObject);
      var highlighted = highlight.parse(yaml, language: 'yaml');
      var html = highlighted.toHtml();
      var regExp = RegExp(r'(https?://[\w/:%#\$&\?\(\)~\.=\+\-]+)');
      var clickable = html.replaceAllMapped(regExp,
          (m) => '<a href="${m.group(1)}" target="_blank">${m.group(1)}</a>');
      formatted =
          '<html><head><style type="text/css">span.hljs-attr {color:blue;}'
          '</style></head><body><pre>$clickable</pre></body></html>';
      break;
    default:
      print(argParser.usage);
      exit(1);
  }

  print(formatted);
}

String myJson2yaml(dynamic jsonObject) {
  if (jsonObject is Map) {
    return json2yaml(jsonObject.cast<String, dynamic>()).trimRight();
  }
  var sb = StringBuffer();
  for (var r in jsonObject) {
    if (r != jsonObject.first) {
      sb.writeln();
    }
    sb.write(json2yaml(r.cast<String, dynamic>()));
  }
  return sb.toString().trimRight();
}
