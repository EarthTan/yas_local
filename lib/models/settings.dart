class AppSettings {
  final String apiKey;
  final String baseUrl;
  final String vlModel;
  final String textModel;
  final bool debugMode;

  const AppSettings({
    this.apiKey = '',
    this.baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    this.vlModel = 'qwen-vl-max',
    this.textModel = 'qwen-plus',
    this.debugMode = false,
  });

  bool get isConfigured => apiKey.trim().isNotEmpty;

  AppSettings copyWith({
    String? apiKey,
    String? baseUrl,
    String? vlModel,
    String? textModel,
    bool? debugMode,
  }) =>
      AppSettings(
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        vlModel: vlModel ?? this.vlModel,
        textModel: textModel ?? this.textModel,
        debugMode: debugMode ?? this.debugMode,
      );

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'vlModel': vlModel,
        'textModel': textModel,
        'debugMode': debugMode,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        apiKey: json['apiKey'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ??
            'https://dashscope.aliyuncs.com/compatible-mode/v1',
        vlModel: json['vlModel'] as String? ?? 'qwen-vl-max',
        textModel: json['textModel'] as String? ?? 'qwen-plus',
        debugMode: json['debugMode'] as bool? ?? false,
      );
}
