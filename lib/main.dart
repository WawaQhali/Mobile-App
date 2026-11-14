import 'package:flutter/material.dart';

import 'app.dart';
import 'data/db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.cargar();
  runApp(const WawaQhaliApp());
}
