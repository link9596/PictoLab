class AppConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String projectId;
  final String projectPath;
  final String privateToken;
  final String branch;
  final bool enableRename;

  AppConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.projectId,
    required this.projectPath,
    required this.privateToken,
    required this.branch,
    this.enableRename = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'projectId': projectId,
        'projectPath': projectPath,
        'privateToken': privateToken,
        'branch': branch,
        'enableRename': enableRename,
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        id: json['id'],
        name: json['name'],
        baseUrl: json['baseUrl'],
        projectId: json['projectId'],
        projectPath: json['projectPath'],
        privateToken: json['privateToken'],
        branch: json['branch'],
        enableRename: json['enableRename'] ?? false,
      );

  AppConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? projectId,
    String? projectPath,
    String? privateToken,
    String? branch,
    bool? enableRename,
  }) {
    return AppConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      projectId: projectId ?? this.projectId,
      projectPath: projectPath ?? this.projectPath,
      privateToken: privateToken ?? this.privateToken,
      branch: branch ?? this.branch,
      enableRename: enableRename ?? this.enableRename,
    );
  }
}