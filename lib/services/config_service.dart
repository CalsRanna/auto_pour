import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:tapster/models/tapster_config.dart';
import 'package:tapster/utils/config_validator.dart';

class ConfigService {
  static const String defaultConfigFile = '.tapster.yaml';

  Future<TapsterConfig> loadConfig(String? configPath) async {
    final path = configPath ?? defaultConfigFile;
    final file = File(path);

    if (!await file.exists()) {
      throw ConfigException('Configuration file not found: $path');
    }

    try {
      final content = await file.readAsString();
      final yamlMap = loadYaml(content) as YamlMap;
      final jsonMap = json.decode(json.encode(yamlMap)) as Map<String, dynamic>;

      final migratedMap = _migrateLegacyFormat(jsonMap);
      final config = TapsterConfig.fromJson(migratedMap);

      // Validate configuration
      final validator = ConfigValidator();
      final validationResult = validator.validate(config);
      if (!validationResult.isValid) {
        throw ConfigException(
          'Configuration validation failed:\n${validationResult.errors.join('\n')}'
        );
      }

      return config;
    } on YamlException catch (e) {
      throw ConfigException('Invalid YAML format: ${e.message}');
    } on FormatException catch (e) {
      throw ConfigException('Invalid configuration format: ${e.message}');
    } on FileSystemException catch (e) {
      throw ConfigException('Failed to read configuration file: ${e.message}');
    }
  }

  Future<void> saveConfig(TapsterConfig config, String? configPath) async {
    final path = configPath ?? defaultConfigFile;
    final file = File(path);

    // Validate before saving
    final validator = ConfigValidator();
    final validationResult = validator.validate(config);
    if (!validationResult.isValid) {
      throw ConfigException(
        'Configuration validation failed:\n${validationResult.errors.join('\n')}'
      );
    }

    try {
      final content = _generateConfigContent(config);
      await file.writeAsString(content);
    } on FileSystemException catch (e) {
      throw ConfigException('Failed to write configuration file: ${e.message}');
    }
  }

  Future<bool> configExists(String? configPath) async {
    final path = configPath ?? defaultConfigFile;
    final file = File(path);
    return await file.exists();
  }

  Map<String, dynamic> _migrateLegacyFormat(Map<String, dynamic> json) {
    // If already has nested structure, return as-is
    if (json.containsKey('formula') || json.containsKey('cask') || json.containsKey('scoop')) {
      return json;
    }

    // Legacy flat format detected — wrap into formula sub-config
    if (json.containsKey('tap')) {
      final formulaMap = <String, dynamic>{
        'tap': json['tap'],
        'asset': json['asset'],
        if (json['checksum'] != null) 'checksum': json['checksum'],
        'dependencies': json['dependencies'] ?? [],
      };

      final migrated = Map<String, dynamic>.from(json);
      migrated['formula'] = formulaMap;
      migrated.remove('tap');
      migrated.remove('asset');
      migrated.remove('checksum');
      migrated.remove('dependencies');
      return migrated;
    }

    return json;
  }

  String _generateConfigContent(TapsterConfig config) {
    final buffer = StringBuffer();

    buffer.writeln('# Tapster Configuration File');
    buffer.writeln('# This file defines how your package should be built and published');
    buffer.writeln();

    buffer.writeln('name: ${config.name}');
    buffer.writeln('version: ${config.version}');
    buffer.writeln('description: ${config.description}');
    buffer.writeln('homepage: ${config.homepage}');
    buffer.writeln('repository: ${config.repository}');
    buffer.writeln('license: ${config.license}');

    if (config.formula != null) {
      _writeFormulaSection(buffer, config.formula!);
    }

    if (config.cask != null) {
      _writeCaskSection(buffer, config.cask!);
    }

    if (config.scoop != null) {
      _writeScoopSection(buffer, config.scoop!);
    }

    return buffer.toString();
  }

  void _writeFormulaSection(StringBuffer buffer, FormulaConfig f) {
    buffer.writeln();
    buffer.writeln('formula:');
    buffer.writeln('  tap: ${f.tap}');
    buffer.writeln('  asset: ${f.asset}');
    if (f.checksum != null) {
      buffer.writeln('  checksum: ${f.checksum}');
    }
    if (f.dependencies.isNotEmpty) {
      buffer.writeln('  dependencies:');
      for (final dep in f.dependencies) {
        buffer.writeln('    - $dep');
      }
    }
  }

  void _writeCaskSection(StringBuffer buffer, CaskConfig c) {
    buffer.writeln();
    buffer.writeln('cask:');
    buffer.writeln('  tap: ${c.tap}');
    buffer.writeln('  asset: ${c.asset}');
    buffer.writeln('  app_name: ${c.appName}');
    if (c.checksum != null) {
      buffer.writeln('  checksum: ${c.checksum}');
    }
  }

  void _writeScoopSection(StringBuffer buffer, ScoopConfig s) {
    buffer.writeln();
    buffer.writeln('scoop:');
    buffer.writeln('  bucket: ${s.bucket}');
    buffer.writeln('  asset: ${s.asset}');
    buffer.writeln('  arch: ${s.arch}');
    if (s.checksum != null) {
      buffer.writeln('  checksum: ${s.checksum}');
    }
    if (s.shortcuts.isNotEmpty) {
      buffer.writeln('  shortcuts:');
      for (final sc in s.shortcuts) {
        buffer.writeln('    - $sc');
      }
    }
  }
}

class ConfigException implements Exception {
  final String message;

  ConfigException(this.message);

  @override
  String toString() => message;
}