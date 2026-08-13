import 'dart:io';
import 'package:tapster/models/tapster_config.dart';

class ValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  ValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });
}

class ConfigValidator {
  ValidationResult validate(TapsterConfig config) {
    final errors = <String>[];
    final warnings = <String>[];

    // Validate required fields
    if (config.name.trim().isEmpty) {
      errors.add('Package name is required');
    } else if (!_isValidPackageName(config.name)) {
      errors.add('Invalid package name: ${config.name}');
    }

    // version 可选（版本来自远端 Release tag，配置生成后无需维护）；
    // 提供时仅校验格式
    final version = config.version;
    if (version != null && version.trim().isNotEmpty && !_isValidVersion(version)) {
      errors.add('Invalid version format: $version');
    }

    if (config.description.trim().isEmpty) {
      errors.add('Description is required');
    }

    if (config.homepage.trim().isEmpty) {
      errors.add('Homepage is required');
    } else if (!_isValidUrl(config.homepage)) {
      errors.add('Invalid homepage URL: ${config.homepage}');
    }

    if (config.repository.trim().isEmpty) {
      errors.add('Repository URL is required');
    } else if (!_isValidUrl(config.repository)) {
      errors.add('Invalid repository URL: ${config.repository}');
    }

    if (config.license.trim().isEmpty) {
      errors.add('License is required');
    }

    // Validate at least one distribution target exists
    if (config.formula == null && config.cask == null && config.scoop == null) {
      errors.add('At least one distribution target (formula, cask, or scoop) must be configured');
    }

    // Validate formula section
    if (config.formula != null) {
      _validateFormula(config.formula!, errors, warnings);
    }

    // Validate cask section
    if (config.cask != null) {
      _validateCask(config.cask!, errors, warnings);
    }

    // Validate scoop section
    if (config.scoop != null) {
      _validateScoop(config.scoop!, errors, warnings);
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  void _validateFormula(FormulaConfig f, List<String> errors, List<String> warnings) {
    if (f.tap.trim().isEmpty) {
      errors.add('formula.tap is required');
    }
    if (f.asset.trim().isEmpty) {
      errors.add('formula.asset is required');
    } else {
      final file = File(f.asset);
      if (!file.existsSync()) {
        warnings.add('formula.asset file not found: ${f.asset}');
      }
    }
    if (f.linuxAsset != null && f.linuxAsset!.trim().isNotEmpty) {
      final linuxFile = File(f.linuxAsset!);
      if (!linuxFile.existsSync()) {
        warnings.add('formula.linux_asset file not found: ${f.linuxAsset}');
      }
    }
    if (f.checksum != null && f.checksum!.isNotEmpty) {
      warnings.add('formula.checksum is configured — it may go stale; '
          'the remote release digest is authoritative. '
          'Consider removing it from .tapster.yaml');
    }
    for (final dep in f.dependencies) {
      if (dep.trim().isEmpty) {
        warnings.add('Empty formula dependency found');
      }
    }
  }

  void _validateCask(CaskConfig c, List<String> errors, List<String> warnings) {
    if (c.tap.trim().isEmpty) {
      errors.add('cask.tap is required');
    }
    if (c.asset.trim().isEmpty) {
      errors.add('cask.asset is required');
    } else {
      final file = File(c.asset);
      if (!file.existsSync()) {
        warnings.add('cask.asset file not found: ${c.asset}');
      }
    }
    if (c.appName.trim().isEmpty) {
      errors.add('cask.app_name is required');
    } else if (!c.appName.endsWith('.app')) {
      warnings.add('cask.app_name should end with .app: ${c.appName}');
    }
  }

  void _validateScoop(ScoopConfig s, List<String> errors, List<String> warnings) {
    if (s.bucket.trim().isEmpty) {
      errors.add('scoop.bucket is required');
    }
    if (s.asset.trim().isEmpty) {
      errors.add('scoop.asset is required');
    } else {
      final file = File(s.asset);
      if (!file.existsSync()) {
        warnings.add('scoop.asset file not found: ${s.asset}');
      }
      if (s.bin == null || s.bin!.trim().isEmpty) {
        // 契约提示：bin 缺省按 asset 基名推导
        final normalized = s.asset.replaceAll('\\', '/');
        final fileName = normalized.split('/').last;
        final derived = fileName.endsWith('.zip')
            ? fileName.substring(0, fileName.length - 4)
            : fileName;
        warnings.add('scoop.bin not set — the zip must contain '
            '"$derived.exe"; set scoop.bin explicitly if it differs');
      }
    }
    if (s.bin != null && s.bin!.trim().isNotEmpty && !s.bin!.endsWith('.exe')) {
      warnings.add('scoop.bin should end with .exe: ${s.bin}');
    }
    if (s.checksum != null && s.checksum!.isNotEmpty) {
      warnings.add('scoop.checksum is configured — it may go stale; '
          'the remote release digest is authoritative. '
          'Consider removing it from .tapster.yaml');
    }
    if (!['64bit', '32bit', 'arm64'].contains(s.arch)) {
      warnings.add('scoop.arch should be 64bit, 32bit, or arm64, got: ${s.arch}');
    }
  }

  bool _isValidPackageName(String name) {
    if (name.isEmpty) return false;

    // Package names should contain only lowercase letters, numbers, and hyphens
    // and cannot start or end with a hyphen
    final regex = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');
    return regex.hasMatch(name);
  }

  bool _isValidVersion(String version) {
    if (version.isEmpty) return false;

    // Semantic versioning pattern: x.y.z with optional pre-release and build metadata
    final regex = RegExp(r'^\d+\.\d+\.\d+(-[a-zA-Z0-9-]+)?(\+[a-zA-Z0-9-]+)?$');
    return regex.hasMatch(version);
  }

  bool _isValidUrl(String url) {
    if (url.isEmpty) return false;

    // Basic URL validation
    return url.startsWith('http://') ||
           url.startsWith('https://') ||
           url.startsWith('git@');
  }
}