import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

class GitLabService {
  final Dio _dio = Dio();

  String _baseUrl;
  String _projectId;
  String _projectPath;
  String _privateToken;
  String _branch;

  GitLabService({
    required String baseUrl,
    required String projectId,
    required String projectPath,
    required String privateToken,
    String branch = "main",
  })  : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _projectId = projectId,
        _projectPath = projectPath,
        _privateToken = privateToken,
        _branch = branch;

  void updateConfig({
    String? baseUrl,
    String? projectId,
    String? projectPath,
    String? privateToken,
    String? branch,
  }) {
    if (baseUrl != null) _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    _projectId = projectId ?? _projectId;
    _projectPath = projectPath ?? _projectPath;
    _privateToken = privateToken ?? _privateToken;
    _branch = branch ?? _branch;
  }

  String getRawUrl(String filePath) {
    return '$_baseUrl/$_projectPath/-/raw/$_branch/$filePath';
  }

  // 通用上传方法，支持自定义文件名
  Future<Map<String, dynamic>> uploadFile(
    XFile file, {
    void Function(int sent, int total)? onProgress,
    String? customFileName,
  }) async {
    File localFile = File(file.path);
    List<int> fileBytes = await localFile.readAsBytes();
    String base64Content = base64Encode(fileBytes);

    String extension = path.extension(file.name);
    String fileName;
    if (customFileName != null && customFileName.isNotEmpty) {
      // 如果没有扩展名自动加上
      if (!customFileName.contains('.')) {
        fileName = '$customFileName$extension';
      } else {
        fileName = customFileName;
      }
    } else {
      String uuid = Uuid().v4();
      fileName = "$uuid$extension";
    }

    final now = DateTime.now();
    final yearMonthDir = '${now.year}/${now.month.toString().padLeft(2, '0')}';
    final filePath = "$yearMonthDir/$fileName";

    String encodedFilePath = Uri.encodeComponent(filePath);
    String url = '$_baseUrl/api/v4/projects/$_projectId/repository/files/$encodedFilePath';

    Map<String, dynamic> data = {
      "branch": _branch,
      "content": base64Content,
      "commit_message": "Upload file $fileName to $yearMonthDir via App",
      "encoding": "base64",
    };

    try {
      final Response response = await _dio.post(
        url,
        data: jsonEncode(data),
        options: Options(
          headers: {
            'PRIVATE-TOKEN': _privateToken,
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => status! < 500,
        ),
        onSendProgress: onProgress,
      );

      if (response.statusCode == 201) {
        String rawUrl = getRawUrl(filePath);
        return {
          "markdown": "![$fileName]($rawUrl)",
          "url": rawUrl,
          "file_path": filePath,
          "name": fileName,
        };
      } else {
        throw Exception('上传失败: ${response.statusCode} - ${response.data}');
      }
    } catch (e) {
      print('Upload error: $e');
      throw Exception('上传错误: $e');
    }
  }

  Future<void> deleteImage(String filePath) async {
    String encodedFilePath = Uri.encodeComponent(filePath);
    String url = '$_baseUrl/api/v4/projects/$_projectId/repository/files/$encodedFilePath';
    try {
      final Response response = await _dio.delete(
        url,
        data: {"branch": _branch, "commit_message": "Delete file $filePath via App"},
        options: Options(headers: {'PRIVATE-TOKEN': _privateToken}),
      );
      if (response.statusCode != 204) {
        throw Exception('删除失败，状态码：${response.statusCode}');
      }
    } catch (e) {
      print('Delete error: $e');
      throw Exception('删除错误: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getUploadedFiles() async {
    return await _getAllFiles('');
  }

  Future<List<Map<String, dynamic>>> _getAllFiles(String currentPath) async {
    String url = '$_baseUrl/api/v4/projects/$_projectId/repository/tree?ref=$_branch';
    if (currentPath.isNotEmpty) {
      url += '&path=${Uri.encodeComponent(currentPath)}';
    }
    try {
      final Response response = await _dio.get(
        url,
        options: Options(headers: {'PRIVATE-TOKEN': _privateToken}),
      );
      if (response.statusCode != 200) {
        throw Exception('获取列表失败，状态码：${response.statusCode}');
      }
      List<dynamic> items = response.data;
      List<Map<String, dynamic>> files = [];
      for (var item in items) {
        if (item['type'] == 'blob') {
          files.add(item as Map<String, dynamic>);
        } else if (item['type'] == 'tree') {
          final subFiles = await _getAllFiles(item['path']);
          files.addAll(subFiles);
        }
      }
      return files;
    } catch (e) {
      print('Get files error: $e');
      throw Exception('获取文件列表错误: $e');
    }
  }
}