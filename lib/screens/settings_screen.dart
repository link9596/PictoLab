import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:clipboard/clipboard.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';
import '../services/config_manager.dart';

class SettingsScreen extends StatefulWidget {
  final FlutterSecureStorage storage;
  final VoidCallback onSettingsChanged;

  const SettingsScreen({
    Key? key,
    required this.storage,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ConfigManager _configManager = ConfigManager();
  List<AppConfig> _configs = [];
  AppConfig? _currentConfig;
  bool _isLoading = true;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = packageInfo.version;
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final configs = await _configManager.loadConfigs();
    final current = await _configManager.getCurrentConfig();
    setState(() {
      _configs = configs;
      _currentConfig = current;
      _isLoading = false;
    });
  }

  Future<void> _saveCurrentConfig(AppConfig config) async {
    await _configManager.updateConfig(config);
    if (_currentConfig?.id == config.id) {
      setState(() => _currentConfig = config);
    }
    await _loadData();
    widget.onSettingsChanged();
  }

  void _editConfig(AppConfig? config) async {
    final isEditing = config != null;
    final dialogConfig = config ??
        AppConfig(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: '',
          baseUrl: '',
          projectId: '',
          projectPath: '',
          privateToken: '',
          branch: 'main',
          enableRename: false,
        );
    final nameController = TextEditingController(text: dialogConfig.name);
    final baseUrlController = TextEditingController(text: dialogConfig.baseUrl);
    final projectIdController = TextEditingController(text: dialogConfig.projectId);
    final projectPathController = TextEditingController(text: dialogConfig.projectPath);
    final tokenController = TextEditingController(text: dialogConfig.privateToken);
    final branchController = TextEditingController(text: dialogConfig.branch);
    bool enableRename = dialogConfig.enableRename;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? '编辑配置' : '新增配置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '配置名称 *', hintText: '例如：我的GitLab'),
                ),
                TextField(
                  controller: baseUrlController,
                  decoration: const InputDecoration(labelText: 'GitLab服务器地址 *'),
                ),
                TextField(
                  controller: projectIdController,
                  decoration: const InputDecoration(labelText: '项目 ID (数字) *'),
                ),
                TextField(
                  controller: projectPathController,
                  decoration: const InputDecoration(labelText: '项目路径（组/项目名） *'),
                ),
                TextField(
                  controller: tokenController,
                  decoration: const InputDecoration(labelText: 'Private Token *'),
                  obscureText: true,
                ),
                TextField(
                  controller: branchController,
                  decoration: const InputDecoration(labelText: '分支名称'),
                ),
                Row(
                  children: [
                    const Text('上传前重命名'),
                    const SizedBox(width: 12),
                    Switch(
                      value: enableRename,
                      onChanged: (val) => setDialogState(() => enableRename = val),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final newConfig = AppConfig(
                  id: isEditing ? dialogConfig.id : DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  baseUrl: baseUrlController.text.trim(),
                  projectId: projectIdController.text.trim(),
                  projectPath: projectPathController.text.trim(),
                  privateToken: tokenController.text.trim(),
                  branch: branchController.text.trim().isEmpty ? 'main' : branchController.text.trim(),
                  enableRename: enableRename,
                );
                if (isEditing) {
                  await _configManager.updateConfig(newConfig);
                } else {
                  await _configManager.addConfig(newConfig);
                }
                await _loadData();
                widget.onSettingsChanged();
                if (mounted) Navigator.pop(context);
              },
              child: Text(isEditing ? '保存' : '创建'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteConfig(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后不可恢复，确定要删除此配置吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    await _configManager.deleteConfig(id);
    await _loadData();
    widget.onSettingsChanged();
  }

  Future<void> _setCurrentConfig(String id) async {
    await _configManager.setCurrentConfigId(id);
    await _loadData();
    widget.onSettingsChanged();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已切换到新配置')));
  }

  void _copyToClipboard(String text, String message) {
    FlutterClipboard.copy(text);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showAboutDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于 PictoLab'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PictoLab - GitLab 图床管理器'),
            const SizedBox(height: 8),
            Text('版本：$_appVersion'),
            const SizedBox(height: 8),
            const Text('作者：Link'),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _copyToClipboard('https://atlinker.cn', '链接已复制'),
              child: Text(
                'https://atlinker.cn',
                style: TextStyle(
                  color: isDark ? Colors.lightBlueAccent : Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('交流与反馈'),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _copyToClipboard('https://atlinker.cn/pages/Hydrogen.html', '链接已复制'),
              child: Text(
                'https://atlinker.cn/pages/Hydrogen.html',
                style: TextStyle(
                  color: isDark ? Colors.lightBlueAccent : Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCaches() async {
    final snackBar = SnackBar(content: Text('正在清理缓存...'));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);

    try {
      await DefaultCacheManager().emptyCache();

      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
        await tempDir.create();
      }

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存已清理'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清理失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 2,
            color: isDark ? const Color(0xFF191C20) : Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('当前激活的配置', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_currentConfig != null) ...[
                    Text('名称：${_currentConfig!.name}', style: const TextStyle(fontSize: 16)),
                    Text('服务器：${_currentConfig!.baseUrl}'),
                    Text('项目：${_currentConfig!.projectPath} (ID: ${_currentConfig!.projectId})'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('上传前重命名：'),
                        Switch(
                          value: _currentConfig!.enableRename,
                          onChanged: (value) async {
                            final updated = _currentConfig!.copyWith(enableRename: value);
                            await _saveCurrentConfig(updated);
                            setState(() => _currentConfig = updated);
                          },
                        ),
                      ],
                    ),
                  ] else ...[
                    const Text('暂无配置，请点击下方按钮添加'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('配置方案', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _editConfig(null),
                tooltip: '新增配置',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_configs.isEmpty)
            const Center(child: Text('暂无配置，点击 + 号添加'))
          else
            ..._configs.map(
              (cfg) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: GestureDetector(
                    onTap: () => _setCurrentConfig(cfg.id),
                    child: Icon(
                      _currentConfig?.id == cfg.id ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: _currentConfig?.id == cfg.id ? Colors.green : null,
                    ),
                  ),
                  title: Text(cfg.name),
                  subtitle: Text('${cfg.baseUrl} | ${cfg.projectPath}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'switch') _setCurrentConfig(cfg.id);
                      if (value == 'edit') _editConfig(cfg);
                      if (value == 'delete') _deleteConfig(cfg.id);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'switch', child: Text('切换到此配置')),
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Card(
            color: isDark ? const Color(0xFF191C20) : Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('说明', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('• 可以保存多套 GitLab 配置并切换'),
                  Text('• GitLab生成的Token最长拥有365天有效期哦，如果连接出错请检查Token是否过期'),
                  Text('• 开启“上传前重命名”后，每次上传前都会弹出对话框来自定义文件名（仅限单文件上传）'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              onPressed: _clearCaches,
              icon: const Icon(Icons.cleaning_services),
              label: const Text('清理缓存'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFF191C20) : const Color(0xFFF2F3FA),
                foregroundColor: isDark ? Colors.white : Colors.black,
                elevation: 1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _showAboutDialog,
              icon: const Icon(Icons.info_outline),
              label: const Text('关于'),
            ),
          ),
        ],
      ),
    );
  }
}