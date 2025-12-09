import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public GitHub manifest location. Replace with your repo.
const String manifestUrl =
    'https://raw.githubusercontent.com/your-org/your-repo/main/update.json';

enum UpdateKind { none, optional, mandatory }

class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.mandatory,
    required this.notes,
    required this.url,
    required this.sha256,
    required this.platformKey,
  });

  final String version;
  final bool mandatory;
  final String notes;
  final String url;
  final String sha256;
  final String platformKey;
}

class UpdateCheckResult {
  UpdateCheckResult.none()
      : kind = UpdateKind.none,
        info = null;

  UpdateCheckResult.available(this.kind, this.info);

  final UpdateKind kind;
  final UpdateInfo? info;
}

class UpdateService {
  UpdateService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 30),
        ));

  final Dio _dio;

  String? _platformKey() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return null; // other platforms are ignored for now
  }

  Future<UpdateCheckResult> checkForUpdate() async {
    final platform = _platformKey();
    if (platform == null) return UpdateCheckResult.none();

    final response = await _dio.get<String>(manifestUrl);
    final decoded = jsonDecode(response.data ?? '') as Map<String, dynamic>;
    if (!decoded.containsKey(platform)) return UpdateCheckResult.none();

    final platformData = decoded[platform] as Map<String, dynamic>;
    final targetVersion = platformData['version'] as String? ?? '';
    final mandatory = platformData['mandatory'] as bool? ?? false;
    final notes = platformData['notes'] as String? ?? '';
    final url = platformData['url'] as String? ?? '';
    final sha = platformData['sha256'] as String? ?? '';

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = Version.parse(packageInfo.version);
    final target = Version.parse(targetVersion);
    if (target <= currentVersion) return UpdateCheckResult.none();

    final info = UpdateInfo(
      version: targetVersion,
      mandatory: mandatory,
      notes: notes,
      url: url,
      sha256: sha,
      platformKey: platform,
    );
    return UpdateCheckResult.available(
      mandatory ? UpdateKind.mandatory : UpdateKind.optional,
      info,
    );
  }

  Future<File> downloadUpdate(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final fileName =
        '${info.platformKey}_${info.version}_${info.url.split('/').last}';
    final file = File('${tempDir.path}/$fileName');
    await _dio.download(
      info.url,
      file.path,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );
    await _verifySha(file, info.sha256);
    return file;
  }

  Future<void> _verifySha(File file, String expected) async {
    if (expected.isEmpty) return; // allow empty checksum for testing
    final digest = await sha256.bind(file.openRead()).first;
    final computed = digest.toString();
    if (computed.toLowerCase() != expected.toLowerCase()) {
      throw Exception('Checksum mismatch. Expected $expected, got $computed');
    }
  }

  Future<bool> installUpdate(UpdateInfo info, File file) async {
    if (Platform.isAndroid) {
      await OpenFilex.open(file.path);
      return true;
    }
    if (Platform.isWindows) {
      // Assumes the installer supports silent/quiet install arguments.
      await Process.start(
        file.path,
        ['/SILENT', '/VERYSILENT'],
        mode: ProcessStartMode.detached,
      );
      return true;
    }
    // Fallback: open release URL in browser.
    final uri = Uri.tryParse(info.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}

