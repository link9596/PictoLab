import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:clipboard/clipboard.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_bicubic_resize/flutter_bicubic_resize.dart';
import '../services/gitlab_service.dart';

class UploadScreen extends StatefulWidget {
  final GitLabService gitLabService;
  final FlutterSecureStorage storage;
  final bool enableRename;

  const UploadScreen({
    Key? key,
    required this.gitLabService,
    required this.storage,
    required this.enableRename,
  }) : super(key: key);

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  bool _enableCompression = true;
  int _compressionQuality = 85;

  @override
  void initState() {
    super.initState();
    _loadCompressionSettings();
  }

  Future<void> _loadCompressionSettings() async {
    final enableStr = await widget.storage.read(key: 'upload_enableCompression');
    if (enableStr != null) {
      setState(() => _enableCompression = enableStr == 'true');
    }
    final qualityStr = await widget.storage.read(key: 'upload_compressionQuality');
    if (qualityStr != null) {
      final q = int.tryParse(qualityStr);
      if (q != null) setState(() => _compressionQuality = q.clamp(1, 100));
    }
  }

  Future<void> _saveCompressionSettings() async {
    await widget.storage.write(key: 'upload_enableCompression', value: _enableCompression.toString());
    await widget.storage.write(key: 'upload_compressionQuality', value: _compressionQuality.toString());
  }

  String getQualityLabel() {
    if (!_enableCompression) return '原图（不压缩）';
    return '图片质量: $_compressionQuality%';
  }

/// 生成默认文件名
String _generateDefaultFileName(String originalPath) {
  final now = DateTime.now();
  final dateStr = "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";
  final timestampLast4 = (now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
  final random = Random().nextInt(9000) + 1000;
  final extension = originalPath.split('.').last;
  // 判断是否为视频格式
  final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(extension.toLowerCase());
  final prefix = isVideo ? "video" : "img";
  return "$prefix-$dateStr-$timestampLast4-$random.$extension";
}

  /// 弹出重命名对话框，自动选中扩展名之前的部分
  Future<String?> _showRenameDialog(String originalPath) async {
    final defaultName = _generateDefaultFileName(originalPath);
    final controller = TextEditingController(text: defaultName);
    final dotIndex = defaultName.lastIndexOf('.');
    final selectionEnd = dotIndex != -1 ? dotIndex : defaultName.length;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.selection = TextSelection(baseOffset: 0, extentOffset: selectionEnd);
    });

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名文件'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '请输入文件名（可保留扩展名）',
            helperText: '不修改扩展名将自动保留原格式',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<File> _saveTempFile(Uint8List bytes) async {
    final dir = await Directory.systemTemp.createTemp('compress');
    final file = File('${dir.path}/img_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<XFile> _compressImage(XFile original) async {
    if (!_enableCompression) return original;

    try {
      final bytes = await original.readAsBytes();
      final info = await BicubicResizer.getImageInfoAsync(bytes);
      final int originalWidth = info.width;
      final int originalHeight = info.height;
      final double aspectRatio = originalWidth / originalHeight;

      const int maxDimension = 1920;
      int targetWidth = originalWidth;
      int targetHeight = originalHeight;

      if (originalWidth > maxDimension || originalHeight > maxDimension) {
        if (originalWidth >= originalHeight) {
          targetWidth = maxDimension;
          targetHeight = (maxDimension / aspectRatio).round();
        } else {
          targetHeight = maxDimension;
          targetWidth = (maxDimension * aspectRatio).round();
        }
      }

      final compressedBytes = await BicubicResizer.resizeJpegAsync(
        jpegBytes: bytes,
        outputWidth: targetWidth,
        outputHeight: targetHeight,
        quality: _compressionQuality,
        cropAspectRatio: CropAspectRatio.original,
      );

      final tempFile = await _saveTempFile(compressedBytes);
      final originalSizeKB = await original.length() ~/ 1024;
      final newSizeKB = await tempFile.length() ~/ 1024;
      print('压缩报告: ${originalSizeKB}KB → ${newSizeKB}KB (质量: $_compressionQuality%, 尺寸: ${targetWidth}x${targetHeight})');
      return XFile(tempFile.path);
    } catch (e) {
      print('压缩失败: $e，使用原图');
      return original;
    }
  }

  Future<void> _pickImage() async {
    final XFile? media = await _picker.pickImage(source: ImageSource.gallery);
    if (media == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    XFile fileToUpload = media;
    try {
      fileToUpload = await _compressImage(media);
    } catch (e) {
      print('预处理异常: $e');
      fileToUpload = media;
    }
    await _uploadFile(fileToUpload);
  }

  Future<void> _pickVideo() async {
    final XFile? media = await _picker.pickVideo(source: ImageSource.gallery);
    if (media == null) return;
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });
    await _uploadFile(media, isVideo: true);
  }

  Future<void> _uploadFile(XFile file, {bool isVideo = false}) async {
    String? customName;

    if (widget.enableRename) {
      final newName = await _showRenameDialog(file.name);
      if (newName == null) {
        setState(() => _isUploading = false);
        return;
      }
      customName = newName;
    } else {
      customName = _generateDefaultFileName(file.name);
    }

    try {
      final result = await widget.gitLabService.uploadFile(
        file,
        customFileName: customName,
        onProgress: (sent, total) {
          setState(() {
            _uploadProgress = sent / total;
          });
        },
      );
      setState(() => _isUploading = false);
      _showSuccessDialog(result['markdown'], result['url'], result['name']);
    } catch (e) {
      setState(() => _isUploading = false);
      _showErrorDialog('上传失败: $e');
    }
  }

  // UI 辅助方法
  void _showSuccessDialog(String markdownLink, String rawUrl, String fileName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [Icon(Icons.check_circle, color: Colors.green), const SizedBox(width: 8), const Text('上传成功')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件名: $fileName'),
            const SizedBox(height: 8),
            const Text('Markdown 链接:', style: TextStyle(fontWeight: FontWeight.bold)),
            SelectableText(markdownLink, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            const Text('原始链接:', style: TextStyle(fontWeight: FontWeight.bold)),
            SelectableText(rawUrl, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              FlutterClipboard.copy(markdownLink);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Markdown已复制')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制Markdown'),
          ),
          TextButton.icon(
            onPressed: () {
              FlutterClipboard.copy(rawUrl);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('原始链接已复制')));
            },
            icon: const Icon(Icons.link),
            label: const Text('复制链接'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [Icon(Icons.error, color: Colors.red), const SizedBox(width: 8), const Text('上传失败')]),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_upload, size: 100, color: Colors.blue),
              const SizedBox(height: 20),
              Text('支持图片和视频', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
              const SizedBox(height: 24),

              // 上传按钮区域
              if (_isUploading) ...[
                LinearProgressIndicator(value: _uploadProgress),
                const SizedBox(height: 8),
                Text('上传中 ${(_uploadProgress * 100).toStringAsFixed(0)}%'),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('选择图片'),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                    ),
                    const SizedBox(width: 20),
                    ElevatedButton.icon(
                      onPressed: _pickVideo,
                      icon: const Icon(Icons.video_library),
                      label: const Text('选择视频'),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),

              // 图片压缩板块
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF191C20) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('图片压缩'),
                        Switch(
                          value: _enableCompression,
                          onChanged: (val) {
                            setState(() {
                              _enableCompression = val;
                            });
                            _saveCompressionSettings();
                          },
                        ),
                      ],
                    ),
                    // 动画区域
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: _enableCompression
                          ? Column(
                              children: [
                                const SizedBox(height: 8),
                                Text(getQualityLabel()),
                                Slider(
                                  value: _compressionQuality.toDouble(),
                                  min: 1,
                                  max: 100,
                                  divisions: 99,
                                  label: '${_compressionQuality}%',
                                  onChanged: (val) {
                                    setState(() {
                                      _compressionQuality = val.round();
                                    });
                                    _saveCompressionSettings();
                                  },
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}