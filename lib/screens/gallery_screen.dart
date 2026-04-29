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
  String _currentPath = '';
  List<Map<String, dynamic>> _currentItems = [];
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();

  final Map<String, Future<int>> _sizeFutures = {};

  @override
  void initState() {
    super.initState();
    _loadPage(refresh: true);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
          !_isLoadingMore &&
          _hasMore &&
          !_isLoading &&
          !_isRefreshing) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPage({bool refresh = true}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _hasMore = true;
        _isLoading = true;
        _errorMessage = null;
        _currentItems.clear();
        _sizeFutures.clear();
      });
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final result = await widget.gitLabService.getFilesPage(
        page: _currentPage,
        perPage: 50,
        path: _currentPath.isEmpty ? null : _currentPath,
      );
      setState(() {
        if (refresh) {
          _currentItems = result.files;
        } else {
          _currentItems.addAll(result.files);
        }
        _hasMore = result.hasNext;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    _currentPage++;
    try {
      final result = await widget.gitLabService.getFilesPage(
        page: _currentPage,
        perPage: 50,
        path: _currentPath.isEmpty ? null : _currentPath,
      );
      setState(() {
        _currentItems.addAll(result.files);
        _hasMore = result.hasNext;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    _sizeFutures.clear();
    await _loadPage(refresh: true);
    setState(() => _isRefreshing = false);
  }

  void _enterFolder(String folderPath) {
    setState(() {
      _currentPath = folderPath;
      _currentPage = 1;
      _hasMore = true;
      _isLoading = true;
      _errorMessage = null;
      _currentItems.clear();
      _sizeFutures.clear();
    });
    _loadPage(refresh: true);
  }

  void _goBack() {
    if (_currentPath.isEmpty) return;
    final lastSlash = _currentPath.lastIndexOf('/');
    final parentPath = lastSlash == -1 ? '' : _currentPath.substring(0, lastSlash);
    setState(() {
      _currentPath = parentPath;
      _currentPage = 1;
      _hasMore = true;
      _isLoading = true;
      _errorMessage = null;
      _currentItems.clear();
      _sizeFutures.clear();
    });
    _loadPage(refresh: true);
  }

  bool _isVideo(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);
  }

  String _getRawUrl(String filePath) => widget.gitLabService.getRawUrl(filePath);

  Future<int> _getFileSize(String filePath) {
    if (_sizeFutures.containsKey(filePath)) {
      return _sizeFutures[filePath]!;
    }
    final future = widget.gitLabService.getFileSize(filePath);
    _sizeFutures[filePath] = future;
    return future;
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showExportDialog(Map<String, dynamic> file) {
    final fileName = file['name'];
    final filePath = file['path'];
    final rawUrl = _getRawUrl(filePath);
    final isVideo = _isVideo(fileName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('导出链接 - $fileName'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: isVideo
                ? [
                    // 视频：只显示原始链接和 HTML 链接（video 标签）
                    Text('HTML 链接：', style: TextStyle(fontWeight: FontWeight.bold)),
                    SelectableText('<video src="$rawUrl" controls></video>'),
                    SizedBox(height: 12),
                    Text('原始链接：', style: TextStyle(fontWeight: FontWeight.bold)),
                    SelectableText(rawUrl),
                  ]
                : [
                    // 图片：显示 Markdown、HTML、原始链接
                    Text('Markdown：', style: TextStyle(fontWeight: FontWeight.bold)),
                    SelectableText('![$fileName]($rawUrl)'),
                    SizedBox(height: 8),
                    Text('HTML：', style: TextStyle(fontWeight: FontWeight.bold)),
                    SelectableText('<img src="$rawUrl" alt="$fileName">'),
                    SizedBox(height: 8),
                    Text('原始链接：', style: TextStyle(fontWeight: FontWeight.bold)),
                    SelectableText(rawUrl),
                  ],
          ),
        ),
        actions: [
          if (!isVideo)
            TextButton.icon(
              onPressed: () {
                FlutterClipboard.copy('![$fileName]($rawUrl)');
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Markdown已复制')));
              },
              icon: const Icon(Icons.code),
              label: const Text('复制Markdown'),
            ),
          TextButton.icon(
            onPressed: () {
              FlutterClipboard.copy(isVideo ? '<video src="$rawUrl" controls></video>' : '<img src="$rawUrl" alt="$fileName">');
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('HTML已复制')));
            },
            icon: const Icon(Icons.html),
            label: const Text('复制HTML'),
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

  void _previewImage(String imageUrl) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) => _ImagePreviewPage(imageUrl: imageUrl),
      ),
    );
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${file['name']}" 吗？\n云端也将同步删除'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final filePath = file['path'];
      await widget.gitLabService.deleteImage(filePath);
      await _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('删除成功', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title = _currentPath.isEmpty ? '根目录' : _currentPath;
    final bool showBackButton = _currentPath.isNotEmpty;
    final bool showLoadingIndicator = _isLoading && _currentItems.isEmpty;
    final bool showEmpty = !_isLoading && _currentItems.isEmpty && _errorMessage == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goBack,
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refresh,
            tooltip: '刷新',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: showLoadingIndicator
            ? const Center(child: CircularProgressIndicator())
            : showEmpty
                ? const Center(child: Text('此目录为空'))
                : GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.7,
                    ),
                    itemCount: _currentItems.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _currentItems.length && _isLoadingMore) {
                        return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                      }
                      final item = _currentItems[index];
                      final isFolder = item['type'] == 'tree';
                      final name = item['name'];
                      final path = item['path'];

                      return _FadeInCard(
                        child: isFolder
                            ? Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                child: InkWell(
                                  onTap: () => _enterFolder(path),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.folder, size: 60, color: Colors.amber),
                                      const SizedBox(height: 8),
                                      Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                              )
                            : Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: _isVideo(name) ? null : () => _previewImage(_getRawUrl(path)),
                                        child: ClipRRect(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                          child: _isVideo(name)
                                              ? Container(color: Colors.grey[300], child: const Icon(Icons.video_library, size: 60, color: Colors.blue))
                                              : CachedNetworkImage(
                                                  imageUrl: _getRawUrl(path),
                                                  fit: BoxFit.cover,
                                                  width: double.infinity,
                                                  placeholder: (context, url) => Container(color: Colors.grey[200], child: const Center(child: CircularProgressIndicator())),
                                                  errorWidget: (context, url, error) => Container(color: Colors.grey[300], child: const Icon(Icons.broken_image, size: 40)),
                                                ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        children: [
                                          Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                          const SizedBox(height: 2),
                                          FutureBuilder<int>(
                                            future: _getFileSize(path),
                                            builder: (context, snapshot) {
                                              if (snapshot.hasData && snapshot.data! > 0) {
                                                return Text(_formatFileSize(snapshot.data!), style: const TextStyle(fontSize: 10, color: Colors.grey));
                                              } else if (snapshot.hasError) {
                                                return const SizedBox.shrink();
                                              } else {
                                                return const SizedBox(
                                                  height: 14,
                                                  child: Center(child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1))),
                                                );
                                              }
                                            },
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.copy, size: 18),
                                                onPressed: () {
                                                  FlutterClipboard.copy(_getRawUrl(path));
                                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
                                                },
                                                tooltip: '复制链接',
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.share, size: 18),
                                                onPressed: () => _showExportDialog(item),
                                                tooltip: '导出链接',
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                                onPressed: () => _deleteFile(item),
                                                tooltip: '删除',
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _FadeInCard extends StatefulWidget {
  final Widget child;
  const _FadeInCard({required this.child});

  @override
  State<_FadeInCard> createState() => _FadeInCardState();
}

class _FadeInCardState extends State<_FadeInCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _animation, child: widget.child);
}

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
            initialScale: PhotoViewComputedScale.contained,
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
            enableRotation: false,
          ),
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