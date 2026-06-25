class TapsterConfig {
  final String name;
  final String version;
  final String description;
  final String homepage;
  final String repository;
  final String license;
  final FormulaConfig? formula;
  final CaskConfig? cask;
  final ScoopConfig? scoop;

  TapsterConfig({
    required this.name,
    required this.version,
    required this.description,
    required this.homepage,
    required this.repository,
    required this.license,
    this.formula,
    this.cask,
    this.scoop,
  });

  factory TapsterConfig.fromJson(Map<String, dynamic> json) {
    return TapsterConfig(
      name: json['name'] as String,
      version: json['version'] as String,
      description: json['description'] as String,
      homepage: json['homepage'] as String,
      repository: json['repository'] as String,
      license: json['license'] as String,
      formula: json['formula'] != null
          ? FormulaConfig.fromJson(json['formula'] as Map<String, dynamic>)
          : null,
      cask: json['cask'] != null
          ? CaskConfig.fromJson(json['cask'] as Map<String, dynamic>)
          : null,
      scoop: json['scoop'] != null
          ? ScoopConfig.fromJson(json['scoop'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'version': version,
      'description': description,
      'homepage': homepage,
      'repository': repository,
      'license': license,
      if (formula != null) 'formula': formula!.toJson(),
      if (cask != null) 'cask': cask!.toJson(),
      if (scoop != null) 'scoop': scoop!.toJson(),
    };
  }

  TapsterConfig copyWith({
    String? name,
    String? version,
    String? description,
    String? homepage,
    String? repository,
    String? license,
    FormulaConfig? formula,
    CaskConfig? cask,
    ScoopConfig? scoop,
    bool removeFormula = false,
    bool removeCask = false,
    bool removeScoop = false,
  }) {
    return TapsterConfig(
      name: name ?? this.name,
      version: version ?? this.version,
      description: description ?? this.description,
      homepage: homepage ?? this.homepage,
      repository: repository ?? this.repository,
      license: license ?? this.license,
      formula: removeFormula ? null : (formula ?? this.formula),
      cask: removeCask ? null : (cask ?? this.cask),
      scoop: removeScoop ? null : (scoop ?? this.scoop),
    );
  }

  @override
  String toString() {
    return 'TapsterConfig(name: $name, version: $version, '
        'formula: ${formula != null}, cask: ${cask != null}, scoop: ${scoop != null})';
  }
}

class FormulaConfig {
  final String tap;
  final String asset;
  final String? checksum;
  final List<String> dependencies;

  FormulaConfig({
    required this.tap,
    required this.asset,
    this.checksum,
    this.dependencies = const [],
  });

  factory FormulaConfig.fromJson(Map<String, dynamic> json) {
    return FormulaConfig(
      tap: json['tap'] as String,
      asset: json['asset'] as String,
      checksum: json['checksum'] as String?,
      dependencies: List<String>.from(json['dependencies'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tap': tap,
      'asset': asset,
      if (checksum != null) 'checksum': checksum,
      'dependencies': dependencies,
    };
  }

  FormulaConfig copyWith({
    String? tap,
    String? asset,
    String? checksum,
    List<String>? dependencies,
  }) {
    return FormulaConfig(
      tap: tap ?? this.tap,
      asset: asset ?? this.asset,
      checksum: checksum ?? this.checksum,
      dependencies: dependencies ?? this.dependencies,
    );
  }
}

class CaskConfig {
  final String tap;
  final String asset;
  final String appName;
  final String? checksum;

  CaskConfig({
    required this.tap,
    required this.asset,
    required this.appName,
    this.checksum,
  });

  factory CaskConfig.fromJson(Map<String, dynamic> json) {
    return CaskConfig(
      tap: json['tap'] as String,
      asset: json['asset'] as String,
      appName: json['app_name'] as String,
      checksum: json['checksum'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tap': tap,
      'asset': asset,
      'app_name': appName,
      if (checksum != null) 'checksum': checksum,
    };
  }

  CaskConfig copyWith({
    String? tap,
    String? asset,
    String? appName,
    String? checksum,
  }) {
    return CaskConfig(
      tap: tap ?? this.tap,
      asset: asset ?? this.asset,
      appName: appName ?? this.appName,
      checksum: checksum ?? this.checksum,
    );
  }
}

class ScoopConfig {
  final String bucket;
  final String asset;
  final String arch;
  final String? checksum;
  final List<String> shortcuts;

  ScoopConfig({
    required this.bucket,
    required this.asset,
    this.arch = '64bit',
    this.checksum,
    this.shortcuts = const [],
  });

  factory ScoopConfig.fromJson(Map<String, dynamic> json) {
    return ScoopConfig(
      bucket: json['bucket'] as String,
      asset: json['asset'] as String,
      arch: json['arch'] as String? ?? '64bit',
      checksum: json['checksum'] as String?,
      shortcuts: List<String>.from(json['shortcuts'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bucket': bucket,
      'asset': asset,
      'arch': arch,
      if (checksum != null) 'checksum': checksum,
      'shortcuts': shortcuts,
    };
  }

  ScoopConfig copyWith({
    String? bucket,
    String? asset,
    String? arch,
    String? checksum,
    List<String>? shortcuts,
  }) {
    return ScoopConfig(
      bucket: bucket ?? this.bucket,
      asset: asset ?? this.asset,
      arch: arch ?? this.arch,
      checksum: checksum ?? this.checksum,
      shortcuts: shortcuts ?? this.shortcuts,
    );
  }
}
