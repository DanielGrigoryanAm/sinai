import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sinai/api/current_user.dart';

/// What the app last saw from the backend, kept on the device so screens
/// show it at once (and without internet), then refresh quietly.
///
/// One folder per account, so another account on this phone never sees
/// it; all of it goes on sign-out.
class LocalCache {
  LocalCache._();

  static final instance = LocalCache._();

  Future<Directory> _root() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/cache');

  Future<File?> _file(String name) async {
    final user = currentUserId();
    if (user == null) return null;
    final dir = Directory('${(await _root()).path}/$user');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$name.json');
  }

  /// The JSON saved under [name], or null when there is none.
  Future<Object?> read(String name) async {
    try {
      final file = await _file(name);
      if (file == null || !await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (e) {
      debugPrint('Cache: could not read $name: $e');
      return null;
    }
  }

  /// Replaces what is saved under [name]. Written aside and moved into
  /// place, so a crash halfway never leaves half a file.
  Future<void> write(String name, Object? json) async {
    try {
      final file = await _file(name);
      if (file == null) return;
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(json), flush: true);
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('Cache: could not write $name: $e');
    }
  }

  Future<void> remove(String name) async {
    try {
      final file = await _file(name);
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Forgets everything, for every account; on sign-out.
  Future<void> clear() async {
    try {
      final root = await _root();
      if (await root.exists()) await root.delete(recursive: true);
    } catch (e) {
      debugPrint('Cache: could not clear: $e');
    }
  }
}
