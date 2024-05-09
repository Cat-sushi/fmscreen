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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:fmscreen/fmscreen.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_gzip/shelf_gzip.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import 'package:fmscreen/pdf.dart';

late Screener screener;
int? cacheSize;
int? serverCount;
int? port;

// Configure routes.
final _router = Router()
  ..get('/s', _singleHandler)
  ..post('/s', _multiHandler)
  ..get('/s/body/<itemId>', _bodyHandler)
  ..get('/s/normalize', _normalizeHandler)
  ..get('/s/pdf', _pdfHandler)
  ..get('/s/restart', _restartHandler);

Future<Response> _singleHandler(Request request) async {
  var q = request.requestedUri.queryParameters['q'];
  if (q == null) {
    return Response.badRequest(body: 'Query is not specified');
  }
  var v = request.requestedUri.queryParameters['v'];
  var vervose = false;
  if (v != null && v == '1') {
    vervose = true;
  }
  var c = request.requestedUri.queryParameters['c'];
  var cache = true;
  if (c != null && c == '0') {
    cache = false;
  }
  var screeningResult =
      await screener.screen(q, verbose: vervose, cache: cache);
  var jsonObject = screeningResult.toJson();
  var jsonString = jsonEncode(jsonObject);
  return Response.ok(jsonString,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

Future<Response> _multiHandler(Request request) async {
  var v = request.requestedUri.queryParameters['v'];
  var vervose = false;
  if (v != null && v == '1') {
    vervose = true;
  }
  var c = request.requestedUri.queryParameters['c'];
  var cache = true;
  if (c != null && c == '0') {
    cache = false;
  }
  String queriesJsonString;
  try {
    queriesJsonString = await request.readAsString();
  } catch (e) {
    return Response.badRequest(body: 'Posted data is not a string');
  }
  var queries = <String>[];
  try {
    queries = (jsonDecode(queriesJsonString) as List<dynamic>).cast<String>();
  } catch (e) {
    return Response.badRequest(body: 'Posted data is not a JSON string list');
  }
  var screeningResults =
      await screener.screenb(queries, cache: cache, verbose: vervose);
  var jsonObject = screeningResults.map((e) => e.toJson()).toList();
  var jsonString = jsonEncode(jsonObject);
  return Response.ok(jsonString,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

Response _bodyHandler(Request request) {
  final itemId = Uri.decodeComponent(request.params['itemId']!);
  var body = screener.itemBody(itemId);
  if (body == null) {
    return Response(408, body: 'session timed out');
  }
  var jsonString = jsonEncode(body);
  return Response.ok(jsonString,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

Response _normalizeHandler(Request request) {
  var q = request.requestedUri.queryParameters['q'];
  if (q == null) {
    return Response.badRequest(body: 'Query is not sepecified');
  }
  var normalizingResult = normalize(q);
  var jsonString = jsonEncode(normalizingResult);
  return Response.ok(jsonString,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

Future<Response> _pdfHandler(Request request) async {
  var q = request.requestedUri.queryParameters['q'];
  if (q == null) {
    return Response.badRequest(body: 'Query is not specified');
  }
  var v = request.requestedUri.queryParameters['v'];
  var vervose = false;
  if (v != null && v == '1') {
    vervose = true;
  }
  var c = request.requestedUri.queryParameters['c'];
  var cache = true;
  if (c != null && c == '0') {
    cache = false;
  }
  var screeningResult =
      await screener.screen(q, verbose: vervose, cache: cache);
  var s = screeningResult.queryStatus.start.toUtc().toIso8601String();
  var outName = s.substring(0, 4) +
      s.substring(5, 7) +
      s.substring(8, 10) +
      s.substring(11, 13) +
      s.substring(14, 16) +
      s.substring(17, 19);
  var uint8data = await generateDocument(screeningResult);
  return Response.ok(
    uint8data,
    headers: {
      'content-type': 'application/pdf',
      'Content-Disposition': 'attachment; filename="juno$outName.pdf"'
    },
  );
}

Future<Response> _restartHandler(Request request) async {
  if (request.requestedUri.host != 'localhost') {
    return Response.badRequest(body: 'Only from localhost');
  }
  print('Restarting servers');
  var newScreener = Screener(cacheSize: cacheSize);
  await newScreener.init();
  var oldScreener = screener;
  screener = newScreener;
  await oldScreener.stopServers();
  return Response.ok('Servers restartd: ${DateTime.now()}\n');
}

void main(List<String> args) async {
  Directory.current = File.fromUri(Platform.script).parent;
  Directory.current = '..';

  final clientHandler = createStaticHandler('assets/flutter/web',
      defaultDocument: 'index.html', serveFilesOutsidePath: true);

  final handler0 = Cascade().add(_router.call).add(clientHandler).handler;

  var argParser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'print this help')
    ..addOption('cache', abbr: 'c', help: 'result chache size')
    ..addOption('server',
        abbr: 's', help: 'number of server threads')
    ..addOption('port', abbr: 'p', valueHelp: 'port');
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

  if (options['cache'] != null) {
    cacheSize = int.tryParse(options['cache'] as String);
  }

  if (options['server'] != null) {
    serverCount = int.tryParse(options['server'] as String);
  }

  if (options['port'] != null) {
    port = int.tryParse(options['port'] as String);
  }

  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // Configure a pipeline that logs requests.
  final handler = Pipeline()
      .addMiddleware(gzipMiddleware)
      .addMiddleware(corsHeaders())
      .addMiddleware(logRequests())
      .addHandler(handler0);

  screener = Screener(cacheSize: cacheSize, serverCount: serverCount);
  await screener.init();

  // For running in containers, we respect the PORT environment variable.
  port ??= int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, ip, port!);
  print('Server listening on port ${server.port}');
}
