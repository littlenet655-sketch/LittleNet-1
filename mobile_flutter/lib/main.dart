import 'package:flutter/material.dart';
import 'api.dart';
import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  await api.restore();
  runApp(LittleNetAppV2(apiClient: api));
}
