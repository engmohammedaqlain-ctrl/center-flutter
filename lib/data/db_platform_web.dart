import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// على الويب لا يوجد SQLite أصلي — نستعمل تنفيذ WASM فوق IndexedDB.
void configureDatabaseFactory() {
  databaseFactory = databaseFactoryFfiWeb;
}
