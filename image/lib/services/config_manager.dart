import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/app_config.dart';

class ConfigManager {
  static const String _configsKey = 'configs';
  static const String _currentConfigIdKey = 'currentConfigId';
  final FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<void> saveConfigs(List<AppConfig> configs) async {
    final jsonList = configs.map((c) => c.toJson()).toList();
    await _storage.write(key: _configsKey, value: jsonEncode(jsonList));
  }

  Future<List<AppConfig>> loadConfigs() async {
    final jsonStr = await _storage.read(key: _configsKey);
    if (jsonStr == null) return [];
    final List<dynamic> list = jsonDecode(jsonStr);
    return list.map((json) => AppConfig.fromJson(json)).toList();
  }

  Future<String?> getCurrentConfigId() async {
    return await _storage.read(key: _currentConfigIdKey);
  }

  Future<void> setCurrentConfigId(String id) async {
    await _storage.write(key: _currentConfigIdKey, value: id);
  }

  Future<AppConfig?> getCurrentConfig() async {
    final configs = await loadConfigs();
    final currentId = await getCurrentConfigId();
    if (currentId == null || configs.isEmpty) return null;
    return configs.firstWhere((c) => c.id == currentId, orElse: () => configs.first);
  }

  Future<void> addConfig(AppConfig config) async {
    final configs = await loadConfigs();
    if (configs.any((c) => c.id == config.id)) return;
    configs.add(config);
    await saveConfigs(configs);
    if (configs.length == 1) await setCurrentConfigId(config.id);
  }

  Future<void> updateConfig(AppConfig config) async {
    final configs = await loadConfigs();
    final index = configs.indexWhere((c) => c.id == config.id);
    if (index != -1) {
      configs[index] = config;
      await saveConfigs(configs);
    }
  }

  Future<void> deleteConfig(String id) async {
    final configs = await loadConfigs();
    configs.removeWhere((c) => c.id == id);
    await saveConfigs(configs);
    final currentId = await getCurrentConfigId();
    if (currentId == id && configs.isNotEmpty) {
      await setCurrentConfigId(configs.first.id);
    } else if (configs.isEmpty) {
      await _storage.delete(key: _currentConfigIdKey);
    }
  }
}