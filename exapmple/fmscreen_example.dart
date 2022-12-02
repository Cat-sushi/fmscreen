import 'dart:convert';
import 'package:fmscreen/fmscreen.dart';

void main(List<String> args) async {
  final screener = Screener();
  await screener.init();

  final result = await screener.screen('abc');

  final resultJsonObject = result.toJson();
  final jsonEncorder = JsonEncoder.withIndent('  ');
  final resultJsonString = jsonEncorder.convert(resultJsonObject);
  print(resultJsonString);

  screener.stopServers();
}
