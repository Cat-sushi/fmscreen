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
    ..addFlag('help', abbr: 'h', negatable: false, help: 'print this help')
    ..addOption('address',
        abbr: 'a',
        defaultsTo: 'http://localhost:8080',
        help: '(http|http)://host(:port)?')
    ..addFlag('cache', abbr: 'c', negatable: false, help: 'activate cache')
    ..addFlag('body',
        abbr: 'b', negatable: false, help: 'fetch item body with ItemId')
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'print item body')
    ..addOption('formatter',
        abbr: 'f', defaultsTo: 'yamly', valueHelp: 'json/yaml/yamly/md/html')
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

  var addr = options['address'] as String;
  var url = Uri.tryParse(addr) ?? Uri.http('localhost:8080');
  if (!url.hasAuthority) {
    print(argParser.usage);
    exit(1);
  }
  var cache = options['cache'] as bool;
  var body = options['body'] as bool;
  var verbose = options['verbose'] as bool;
  var formtter = options['formatter'] as String;
  var normalize = options['normalize'] as bool;
  var restart = options['restart'] as bool;
  var queries = options.rest;

  var httpClient = HttpClient();

  dynamic jsonString;
  if (body) {
    if (queries.length != 1) {
      print(argParser.usage);
      exit(1);
    }
    url = url.replace(path: '/s/body/${queries[0]}');
    try {
      var request = await httpClient.getUrl(url);
      var response = await request.close();
      if (response.statusCode == 408) {
        print('Session timed out.');
        exit(1);
      }
      jsonString = await response.transform(utf8.decoder).join();
    } catch (e) {
      jsonString = '"Server not responding"';
    }
  } else if (normalize) {
    if (queries.length != 1) {
      print(argParser.usage);
      exit(1);
    }
    url = url.replace(path: '/s/normalize', queryParameters: {'q': queries[0]});
    try {
      var request = await httpClient.getUrl(url);
      var response = await request.close();
      jsonString = await response.transform(utf8.decoder).join();
      var normalized = jsonDecode(jsonString);
      print(normalized);
      exit(0);
    } catch (e) {
      jsonString = '"Server not responding"';
    }
  } else if (restart) {
    if (queries.isNotEmpty) {
      print(argParser.usage);
      exit(1);
    }
    url = url.replace(path: '/s/restart');
    try {
      var request = await httpClient.getUrl(url);
      var response = await request.close();
      var responseString = await response.transform(utf8.decoder).join();
      print(responseString);
      httpClient.close();
      exit(0);
    } catch (e) {
      jsonString = '"Server not responding"';
    }
  } else if (queries.isEmpty) {
    print(argParser.usage);
    httpClient.close();
    exit(1);
  } else if (queries.length == 1) {
    url = url.replace(
      path: '/s',
      queryParameters: {
        'c': (cache ? '1' : '0'),
        'v': (verbose ? '1' : '0'),
        'q': queries[0],
      },
    );
    try {
      var request = await httpClient.getUrl(url);
      var response = await request.close();
      jsonString = await response.transform(utf8.decoder).join();
    } catch (e) {
      jsonString = '"Server not responding"';
    }
  } else {
    var queryJsonString = jsonEncode(queries);
    url = url.replace(
      path: '/s',
      queryParameters: {
        'c': (cache ? '1' : '0'),
        'v': (verbose ? '1' : '0'),
      },
    );
    try {
      var request = await httpClient.postUrl(url);
      request.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      request.write(queryJsonString);
      var response = await request.close();
      jsonString = await response.transform(utf8.decoder).join();
    } catch (e) {
      jsonString = '"Server not responding"';
    }
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
    case 'yamly':
      formatted = json2yamly(jsonObject);
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
          '<html><head><style type="text/css">span.hljs-attr {color:brown;}'
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

enum YamlyContext {
  top,
  map,
  list,
}

String json2yamly(dynamic jsonObject) =>
    _json2yamly(jsonObject, 0, YamlyContext.top).trimRight();

final ls = LineSplitter();

String _json2yamly(dynamic jsonObject, int indent, YamlyContext c) {
  var ret = StringBuffer();
  if (jsonObject is Map) {
    var first = true;
    if (c == YamlyContext.map) {
      ret.write('\n');
      first = false;
    }
    for (var e in jsonObject.entries) {
      if (first) {
        first = false;
      } else {
        ret.write('  ' * indent);
      }
      ret.write('${e.key}: ');
      ret.write(_json2yamly(e.value, indent + 1, YamlyContext.map));
    }
  } else if (jsonObject is List) {
    var first = true;
    if (c == YamlyContext.map) {
      ret.write('\n');
      first = false;
    }
    for (var e in jsonObject) {
      if (first) {
        first = false;
      } else {
        ret.write('  ' * indent);
      }
      ret.write('- ');
      ret.write(_json2yamly(e, indent + 1, YamlyContext.list));
    }
  } else if (jsonObject is String) {
    var lines = ls.convert(jsonObject);
    if (lines.length > 1) {
      var first = true;
      if (c == YamlyContext.list || c == YamlyContext.map) {
        ret.write('\n');
        first = false;
      }
      for (var l in lines) {
        if (first) {
          first = false;
        } else {
          ret.write('  ' * indent);
        }
        ret.write('$l\n');
      }
    } else {
      ret.write('$jsonObject\n');
    }
  } else {
    ret.write('$jsonObject\n');
  }
  return ret.toString();
}
