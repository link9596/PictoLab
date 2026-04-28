import 'dart:async';
import 'package:flutter/material.dart';
import 'package:clipboard/clipboard.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/gitlab_service.dart';
import 'package:photo_view/photo_view.dart';

class GalleryScreen extends StatefulWidget {
  final GitLabService gitLabService;

  const GalleryScreen({Key? key, required this.gitLabService}) : super(key: key);

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final files = await widget.gitLabService.getUploadedFiles();
      setState(() {
        _files = files;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  bool _isVideo(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);
  }

  String _getRawUrl(String filePath) {
    return widget.gitLabService.getRawUrl(filePath);
  }

  void _showExportDialog(Map<String, dynamic> file) {
    final fileName = file['name'];
    final filePath = file['path'];
    final rawUrl = _getRawUrl(filePath);
    final markdownLink = '![$fileName]($rawUrl)';
    final htmlLink = '<img src="$rawUrl" alt="$fileName">';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('导出链接 - $fileName'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('原始链接：', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(rawUrl),
              SizedBox(height: 8),
              Text('Markdown：', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(markdownLink),
              SizedBox(height: 8),
              Text('HTML：', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(htmlLink),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              FlutterClipboard.copy(rawUrl);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('原始链接已复制')));
            },
            icon: Icon(Icons.link),
            label: Text('复制链接'),
          ),
          TextButton.icon(
            onPressed: () {
              FlutterClipboard.copy(markdownLink);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Markdown已复制')));
            },
            icon: Icon(Icons.code),
            label: Text('复制Markdown'),
          ),
          TextButton.icon(
            onPressed: () {
              FlutterClipboard.copy(htmlLink);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('HTML已复制')));
            },
            icon: Icon(Icons.html),
            label: Text('复制HTML'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text('关闭')),
        ],
      ),
    );
  }

  // 图片预览
  void _previewImage(String imageUrl) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) =>
            _ImagePreviewPage(imageUrl: imageUrl),
      ),
    );
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('确定要永久删除 "${file['name']}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('正在删除...')));

    try {
      final filePath = file['path'];
      await widget.gitLabService.deleteImage(filePath);
      await _loadFiles();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除成功'), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text('加载失败: $_errorMessage'),
            SizedBox(height: 16),
            ElevatedButton(onPressed: _loadFiles, child: Text('重试')),
          ],
        ),
      );
    }
    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('暂无文件，请先上传'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFiles,
      child: GridView.builder(
        padding: EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.7,
        ),
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final file = _files[index];
          final fileName = file['name'];
          final filePath = file['path'];
          final isVideoFile = _isVideo(fileName);
          final rawUrl = _getRawUrl(filePath);

          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: isVideoFile ? null : () => _previewImage(rawUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                      child: isVideoFile
                          ? Container(
                              color: Colors.grey[300],
                              child: Icon(Icons.video_library, size: 60, color: Colors.blue),
                            )
                          : CachedNetworkImage(
                              imageUrl: rawUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder: (context, url) => Container(color: Colors.grey[200], child: Center(child: CircularProgressIndicator())),
                              errorWidget: (context, url, error) => Container(color: Colors.grey[300], child: Icon(Icons.broken_image, size: 40)),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Text(
                        fileName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12),
                      ),
                      SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(Icons.copy, size: 18),
                            onPressed: () {
                              FlutterClipboard.copy(rawUrl);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('链接已复制')));
                            },
                            tooltip: '复制链接',
                          ),
                          IconButton(
                            icon: Icon(Icons.share, size: 18),
                            onPressed: () => _showExportDialog(file),
                            tooltip: '导出链接',
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, size: 18, color: Colors.red),
                            onPressed: () => _deleteFile(file),
                            tooltip: '删除',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// 预览页面
class _ImagePreviewPage extends StatelessWidget {
  final String imageUrl;
  const _ImagePreviewPage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoView(
            imageProvider: NetworkImage(imageUrl),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            // 初始缩放为适应屏幕（contain）
            initialScale: PhotoViewComputedScale.contained,
            // 最小缩放为适应屏幕，防止缩小到比屏幕还小
            minScale: PhotoViewComputedScale.contained,
            // 最大缩放：屏幕的 3 倍，足够铺满全屏并放大局部细节
            maxScale: PhotoViewComputedScale.covered * 2,
            // 启用双击缩放
            enableRotation: false,
          ),
          // 右上角关闭按钮
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}