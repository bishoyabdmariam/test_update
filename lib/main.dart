import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'update_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Update Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final UpdateService _updateService = UpdateService();

  UpdateCheckResult? _result;
  bool _checking = false;
  bool _installing = false;
  double? _progress;
  String _status = '';
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    _packageInfo = await PackageInfo.fromPlatform();
    await _runCheck(autoPrompt: true);
  }

  Future<void> _runCheck({required bool autoPrompt}) async {
    setState(() {
      _checking = true;
      _status = 'Checking for updates...';
    });
    try {
      final result = await _updateService.checkForUpdate();
      setState(() {
        _result = result;
      });
      if (result.kind == UpdateKind.mandatory && result.info != null) {
        _showMandatoryDialog(result.info!);
      } else if (result.kind == UpdateKind.optional &&
          result.info != null &&
          autoPrompt) {
        _showOptionalDialog(result.info!);
      } else {
        setState(() {
          _status = 'App is up to date.';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Update check failed: $e';
      });
    } finally {
      setState(() {
        _checking = false;
      });
    }
  }

  Future<void> _startUpdate(UpdateInfo info) async {
    setState(() {
      _installing = true;
      _progress = 0;
      _status = 'Downloading update...';
    });
    try {
      final file = await _updateService.downloadUpdate(
        info,
        onProgress: (value) {
          setState(() => _progress = value);
        },
      );
      setState(() {
        _status = 'Launching installer...';
      });
      await _updateService.installUpdate(info, file);
      if (Platform.isWindows) {
        // Windows installer runs outside the app; exit so it can replace files.
        exit(0);
      }
    } catch (e) {
      setState(() {
        _status = 'Update failed: $e';
      });
    } finally {
      setState(() {
        _installing = false;
      });
    }
  }

  void _showOptionalDialog(UpdateInfo info) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${info.version} is available.'),
            const SizedBox(height: 8),
            Text(info.notes.isEmpty ? 'No notes provided.' : info.notes),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _startUpdate(info);
            },
            child: const Text('Update now'),
          ),
        ],
      ),
    );
  }

  void _showMandatoryDialog(UpdateInfo info) {
    showDialog<void>(
      barrierDismissible: false,
      context: context,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('Update required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version ${info.version} is required to continue.'),
              const SizedBox(height: 8),
              Text(
                info.notes.isEmpty ? 'Please update to continue.' : info.notes,
              ),
              if (_progress != null) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text(
                  _progress != null
                      ? 'Downloading ${((_progress ?? 0) * 100).toStringAsFixed(0)}%'
                      : 'Preparing download...',
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => _startUpdate(info),
              child: const Text('Update now'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final versionLabel = _packageInfo != null
        ? '${_packageInfo!.version}+${_packageInfo!.buildNumber}'
        : 'Loading...';

    return Scaffold(
      appBar: AppBar(title: const Text('Update tester')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current version: $versionLabel'),
            const SizedBox(height: 12),
            Text('Status: $_status'),
            const SizedBox(height: 16),
            if (_installing || _checking)
              LinearProgressIndicator(value: _progress),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _checking ? null : () => _runCheck(autoPrompt: true),
              icon: const Icon(Icons.system_update),
              label: const Text('Check for updates'),
            ),
            const SizedBox(height: 12),
            if (_result?.info != null && !_installing)
              ElevatedButton(
                onPressed: () => _startUpdate(_result!.info!),
                child: Text(
                  _result!.kind == UpdateKind.mandatory
                      ? 'Install mandatory update'
                      : 'Install optional update',
                ),
              ),
            const Spacer(),
            const Text(
              'Manifest source:\nhttps://raw.githubusercontent.com/bishoyabdmariam/test_update/main/update.json',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
