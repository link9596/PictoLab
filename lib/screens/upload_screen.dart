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

class _UploadScreenState extends State<UploadScreen> with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();

  // 批量图片上传
  bool _isBatchUploading = false;
  int _batchTotal = 0;
  int _batchCompleted = 0;
  int _batchSuccess = 0;
  int _batchFail = 0;
  bool _batchCancelled = false;
  double _targetBatchProgress = 0.0;
  late AnimationController _batchAnimationController;
  double _animatedBatchProgress = 0.0;

  // 单张图片视频上传共用实时进度
  bool _isSingleUploading = false;
  double _singleProgress = 0.0;

  // 压缩设置
  bool _enableCompression = true;
  int _compressionQuality = 85;

  @override
  void initState() {
    super.initState();
    _loadCompressionSettings();
    _batchAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _batchAnimationController.addListener(() {
      setState(() {
        _animatedBatchProgress = _batchAnimationController.value;
      });
    });
  }

  @override
  void dispose() {
    _batchAnimationController.dispose();
    super.dispose();
  }

  void _setBatchProgress(double target) {
    target = target.clamp(0.0, 1.0);
    if (_batchAnimationController.isAnimating) {
      _batchAnimationController.stop();
    }
    _batchAnimationController.animateTo(target, curve: Curves.easeOutCubic);
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

  String _generateDefaultFileName(String originalPath) {
    final now = DateTime.now();
    final minutesInMonth = (now.day - 1) * 1440 + now.hour * 60 + now.minute;
    const int base = 60000;
    final complement = (base - minutesInMonth).toString().padLeft(5, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final monthDay = "$month$day";
    final random = Random().nextInt(9000) + 1000;
    final extension = originalPath.split('.').last;
    final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(extension.toLowerCase());
    final prefix = isVideo ? "video" : "img";
    return "$prefix-$complement-$monthDay-$random.$extension";
  }

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
      const int maxDimension = 2560;
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
      return XFile(tempFile.path);
    } catch (e) {
      print('压缩失败: $e，使用原图');
      return original;
    }
  }

  // 视频上传
  Future<void> _pickVideo() async {
    final XFile? media = await _picker.pickVideo(source: ImageSource.gallery);
    if (media == null) return;
    setState(() {
      _isSingleUploading = true;
      _singleProgress = 0.0;
    });
    await _uploadVideoFile(media);
  }

  Future<void> _uploadVideoFile(XFile file) async {
    String? customName;
    if (widget.enableRename) {
      final newName = await _showRenameDialog(file.name);
      if (newName == null) {
        setState(() => _isSingleUploading = false);
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
        folderType: 'video',
        onProgress: (sent, total) {
          final progress = total > 0 ? sent / total : 0.0;
          setState(() {
            _singleProgress = progress;
          });
        },
      );
      setState(() => _isSingleUploading = false);
      _showSuccessDialog(result['markdown'], result['url'], result['name']);
    } catch (e) {
      setState(() => _isSingleUploading = false);
      _showErrorDialog('上传失败: $e');
    }
  }

  // 图片上传核心逻辑
  Future<void> _batchPickAndUpload() async {
    final List<XFile>? picked = await _picker.pickMultiImage();
    if (picked == null || picked.isEmpty) return;

    // 单张图片走百分比进度
    if (picked.length == 1) {
      final XFile img = picked[0];
      String? customName;

      // 重命名逻辑
      if (widget.enableRename) {
        customName = await _showRenameDialog(img.name);
        if (customName == null) return;
      } else {
        customName = _generateDefaultFileName(img.name);
      }

      // 初始化单张上传状态
      setState(() {
        _isSingleUploading = true;
        _singleProgress = 0.0;
      });

      // 图片压缩
      XFile toUpload = img;
      if (_enableCompression) {
        try {
          toUpload = await _compressImage(img);
        } catch (e) {
          print('压缩失败: $e');
          toUpload = img;
        }
      }

      // 上传进度回调
      try {
        final result = await widget.gitLabService.uploadFile(
          toUpload,
          customFileName: customName,
          folderType: 'img',
          onProgress: (sent, total) {
            final progress = total > 0 ? sent / total : 0.0;
            setState(() {
              _singleProgress = progress;
            });
          },
        );
        setState(() => _isSingleUploading = false);
        _showSuccessDialog(result['markdown'], result['url'], result['name']);
      } catch (e) {
        setState(() => _isSingleUploading = false);
        _showErrorDialog('上传失败: $e');
      }
      return;
    }

    // 多张图片
    setState(() {
      _isBatchUploading = true;
      _batchTotal = picked.length;
      _batchCompleted = 0;
      _batchSuccess = 0;
      _batchFail = 0;
      _batchCancelled = false;
      _targetBatchProgress = 0.0;
      _animatedBatchProgress = 0.0;
      _setBatchProgress(0.0);
    });

    for (int i = 0; i < picked.length; i++) {
      if (_batchCancelled) break;
      final XFile img = picked[i];
      XFile toUpload = img;
      if (_enableCompression) {
        try {
          toUpload = await _compressImage(img);
        } catch (e) {
          print('压缩失败: $e');
          toUpload = img;
        }
      }
      final customName = _generateDefaultFileName(img.name);
      try {
        final result = await widget.gitLabService.uploadFile(
          toUpload,
          customFileName: customName,
          folderType: 'img',
        );
        setState(() {
          _batchCompleted++;
          _batchSuccess++;
          _targetBatchProgress = _batchCompleted / _batchTotal;
          _setBatchProgress(_targetBatchProgress);
        });
      } catch (e) {
        print('上传失败: $e');
        setState(() {
          _batchCompleted++;
          _batchFail++;
          _targetBatchProgress = _batchCompleted / _batchTotal;
          _setBatchProgress(_targetBatchProgress);
        });
      }
    }

    setState(() {
      _isBatchUploading = false;
    });

    String msg = _batchFail == 0
        ? '批量上传成功 $_batchSuccess 张'
        : '批量上传完成：成功 $_batchSuccess 张，失败 $_batchFail 张';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _batchFail > 0 ? Colors.orange : Colors.green,
      ),
    );
  }

  void _cancelBatchUpload() {
    setState(() {
      _batchCancelled = true;
    });
  }

  void _showSuccessDialog(String markdownLink, String rawUrl, String fileName) {
    final htmlLink = '<img src="$rawUrl" alt="$fileName">';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: const [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('上传成功')
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件名: $fileName'),
            const SizedBox(height: 8),
            const Text('Markdown 链接:', style: TextStyle(fontWeight: FontWeight.bold)),
            SelectableText(markdownLink, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            const Text('HTML 链接:', style: TextStyle(fontWeight: FontWeight.bold)),
            SelectableText(htmlLink, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            const Text('原始链接:', style: TextStyle(fontWeight: FontWeight.bold)),
            SelectableText(rawUrl, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton.icon(
              onPressed: () => _copyAndSnack(markdownLink, 'Markdown已复制'),
              icon: const Icon(Icons.copy),
              label: const Text('复制Markdown')),
          TextButton.icon(
              onPressed: () => _copyAndSnack(htmlLink, 'HTML已复制'),
              icon: const Icon(Icons.html),
              label: const Text('复制HTML')),
          TextButton.icon(
              onPressed: () => _copyAndSnack(rawUrl, '原始链接已复制'),
              icon: const Icon(Icons.link),
              label: const Text('复制链接')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _copyAndSnack(String text, String msg) {
    FlutterClipboard.copy(text);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: const [
          Icon(Icons.error, color: Colors.red),
          SizedBox(width: 8),
          Text('上传失败')
        ]),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isUploading = _isSingleUploading || _isBatchUploading;

    // 进度条判断
    double shownProgress = 0.0;
    String statusText = '';
    bool showCancelButton = false;
    if (_isSingleUploading) {
      // 单张图片视频显示百分比
      shownProgress = _singleProgress;
      statusText = '上传中 ${(_singleProgress * 100).toStringAsFixed(0)}%';
    } else if (_isBatchUploading) {
      // 批量图片进度条
      shownProgress = _animatedBatchProgress;
      statusText = '正在上传 $_batchCompleted / $_batchTotal (成功:$_batchSuccess 失败:$_batchFail)';
      showCancelButton = true;
    }

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
              if (isUploading) ...[
                LinearProgressIndicator(value: shownProgress),
                const SizedBox(height: 8),
                Text(statusText),
                const SizedBox(height: 8),
                if (showCancelButton)
                  ElevatedButton(
                    onPressed: _cancelBatchUpload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 255, 129, 120),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('取消上传'),
                  ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _batchPickAndUpload,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('选择图片'),
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                    ),
                    const SizedBox(width: 20),
                    ElevatedButton.icon(
                      onPressed: _pickVideo,
                      icon: const Icon(Icons.video_library),
                      label: const Text('选择视频'),
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              IgnorePointer(
                ignoring: isUploading,
                child: Opacity(
                  opacity: isUploading ? 0.5 : 1.0,
                  child: Container(
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
                              onChanged: isUploading
                                  ? null
                                  : (val) {
                                      setState(() {
                                        _enableCompression = val;
                                      });
                                      _saveCompressionSettings();
                                    },
                            ),
                          ],
                        ),
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
                                      onChanged: isUploading
                                          ? null
                                          : (val) {
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}