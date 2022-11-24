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

import 'package:fmatch/fmatch.dart';
import 'package:fmscreen/fmscreen.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:simple_mutex/simple_mutex.dart';

late Screener screener;
final mutex = Mutex();

// Configure routes.
final _router = Router()
  ..get('/', _singleHandler)
  ..post('/', _multiHandler)
  ..get('/data/<itemId>', _dataHandler)
  ..get('/normalize', _normalizeHandler)
  ..get('/restart', _restartHandler);

Future<Response> _singleHandler(Request request) async {
  var q = request.requestedUri.queryParameters['q'];
  if (q == null) {
    return Response.badRequest();
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
  await mutex.lockShared();
  var screeningResult =
      await screener.screen(q, verbose: vervose, cache: cache);
  mutex.unlockShared();
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
  var queriesJsonString = await request.readAsString();
  var queries = (jsonDecode(queriesJsonString) as List<dynamic>).cast<String>();
  await mutex.lockShared();
  var screeningResults =
      await screener.screenb(queries, cache: cache, verbose: vervose);
  mutex.unlockShared();
  var jsonObject = screeningResults.map((e) => e.toJson()).toList();
  var jsonString = jsonEncode(jsonObject);
  return Response.ok(jsonString,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

Future<Response> _dataHandler(Request request) async {
  final itemId = Uri.decodeComponent(request.params['itemId']!);
  await mutex.lockShared();
  var data = screener.itemData(itemId);
  mutex.unlockShared();
  if (data == null) {
    return Response(408, body: 'session timed out');
  }
  var jsonString = jsonEncode(data);
  return Response.ok(jsonString,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

Future<Response> _normalizeHandler(Request request) async {
  var q = request.requestedUri.queryParameters['q'];
  if (q == null) {
    return Response.badRequest();
  }
  await mutex.lockShared();
  var normalizingResult = normalize(q);
  mutex.unlockShared();
  var jsonString = jsonEncode(normalizingResult);
  return Response.ok(jsonString,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

Future<Response> _restartHandler(Request request) async {
  await mutex.lock();
  await screener.stopServers();
  screener = Screener();
  await screener.init();
  mutex.unlock();
  return Response.ok('Server restartd: ${DateTime.now()}\n');
}

void main(List<String> args) async {
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // Configure a pipeline that logs requests.
  final handler = Pipeline().addMiddleware(logRequests()).addHandler(_router);

  screener = Screener();
  await screener.init();

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, ip, port);
  print('Server listening on port ${server.port}');
}
