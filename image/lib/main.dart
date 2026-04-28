import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'services/gitlab_service.dart';
import 'services/config_manager.dart';
import 'screens/upload_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/settings_screen.dart';
import 'models/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final FlutterSecureStorage storage = FlutterSecureStorage();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PictoLab',
      theme: ThemeData.light().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 4,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
  ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFFF5F5F5),
          elevation: 4,
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blue.shade900,
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
  ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 4,
        ),
      ),
      themeMode: ThemeMode.system,
      home: MainScreen(storage: storage),
    );
  }
}

class MainScreen extends StatefulWidget {
  final FlutterSecureStorage storage;
  const MainScreen({Key? key, required this.storage}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  GitLabService? _gitLabService;
  bool _isLoading = true;
  final ConfigManager _configManager = ConfigManager();
  AppConfig? _currentConfig;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  Future<void> _loadCurrentConfig() async {
    final config = await _configManager.getCurrentConfig();
    setState(() {
      _currentConfig = config;
      _isLoading = false;
    });
    if (config != null) {
      _gitLabService = GitLabService(
        baseUrl: config.baseUrl,
        projectId: config.projectId,
        projectPath: config.projectPath,
        privateToken: config.privateToken,
        branch: config.branch,
      );
    } else {
      _gitLabService = null;
    }
  }

  void _onSettingsChanged() {
    _loadCurrentConfig();
  }

  @override
  Widget build(BuildContext context) {
    final bottomBarColor = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF1E1E1E);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: bottomBarColor,
        systemNavigationBarDividerColor: bottomBarColor,
        systemNavigationBarIconBrightness:
            Theme.of(context).brightness == Brightness.light ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('PictoLab'), centerTitle: true),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: _selectedIndex,
                children: [
                  _gitLabService == null
                      ? _buildUnconfiguredPage('请先在设置页面配置 GitLab')
                      : UploadScreen(
                          gitLabService: _gitLabService!,
                          storage: widget.storage,
                          enableRename: _currentConfig?.enableRename ?? false,
                        ),
                  _gitLabService == null
                      ? _buildUnconfiguredPage('请先在设置页面配置 GitLab')
                      : GalleryScreen(gitLabService: _gitLabService!),
                  SettingsScreen(
                    storage: widget.storage,
                    onSettingsChanged: _onSettingsChanged,
                  ),
                ],
              ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: bottomBarColor,
          elevation: 4,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.cloud_upload), label: '上传'),
            BottomNavigationBarItem(icon: Icon(Icons.photo_library), label: '相册'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
          ],
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildUnconfiguredPage(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.settings, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => setState(() => _selectedIndex = 2),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}