import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../design/hermes_design.dart';
import '../services/app_update.dart';

class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({super.key, this.serviceFactory});
  final AppUpdateService Function()? serviceFactory;

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  AppUpdateService? _service;
  AppUpdateRelease? _release;
  String? _message;
  String? _installedVersion;
  double? _progress;
  bool _busy = false;
  bool _ready = false;
  bool _permission = false;

  AppUpdateService _start() {
    _service?.close();
    final service = widget.serviceFactory?.call() ?? AppUpdateService();
    _service = service;
    setState(() {
      _busy = true;
      _message = null;
      _permission = false;
    });
    return service;
  }

  String _error(Strings s, Object error) => switch (error) {
    AppUpdateException(kind: AppUpdateError.rateLimit) => s.appUpdateRateLimit,
    AppUpdateException(kind: AppUpdateError.invalidRelease) =>
      s.appUpdateInvalidRelease,
    AppUpdateException(kind: AppUpdateError.integrity) =>
      s.appUpdateIntegrityError,
    AppUpdateException(kind: AppUpdateError.unsupported) =>
      s.appUpdateUnsupported,
    _ => s.appUpdateNetworkError,
  };

  Future<void> _check() async {
    final service = _start();
    setState(() {
      _release = null;
      _ready = false;
      _progress = null;
    });
    try {
      final info = await AppUpdateService.channel
          .invokeMapMethod<String, dynamic>('getInfo');
      if (info?['supported'] != true || info?['versionCode'] is! int) {
        throw const AppUpdateException(AppUpdateError.unsupported);
      }
      final release = await service.check().timeout(const Duration(minutes: 1));
      if (!mounted || _service != service) return;
      final s = Strings.of(context);
      setState(() {
        _installedVersion = '${info!['versionName']} (${info['versionCode']})';
        if (release == null) {
          _message = s.appUpdateNoRelease;
        } else if (!release.isNewerThan(info['versionCode'] as int)) {
          _message = s.appUpdateCurrent;
        } else {
          _release = release;
        }
      });
    } catch (error) {
      if (mounted && _service == service) {
        setState(() => _message = _error(Strings.of(context), error));
      }
    } finally {
      service.close();
      if (mounted && _service == service) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final release = _release!;
    final service = _start();
    setState(() {
      _ready = false;
      _progress = 0;
    });
    try {
      await service.download(release, (value) {
        if (mounted && _service == service) setState(() => _progress = value);
      });
      if (mounted && _service == service) {
        setState(() {
          _ready = true;
          _message = Strings.of(context).appUpdateReady;
        });
      }
    } catch (error) {
      if (mounted && _service == service) {
        setState(() => _message = _error(Strings.of(context), error));
      }
    } finally {
      service.close();
      if (mounted && _service == service) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _message = null;
      _permission = false;
    });
    try {
      final status = await AppUpdateService.install(_release!);
      if (!mounted) return;
      final s = Strings.of(context);
      setState(() {
        _permission = status == 'permission_required';
        _message = switch (status) {
          'permission_required' => s.appUpdatePermissionHelp,
          'installed' => s.appUpdateInstallerFinished,
          _ => s.appUpdateInstallerCancelled,
        };
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _ready = error.code != 'invalid_apk';
          _message = error.code == 'invalid_apk'
              ? Strings.of(context).appUpdateIntegrityError
              : Strings.of(context).appUpdateInstallerError;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = Strings.of(context).appUpdateInstallerError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSources() async {
    try {
      await AppUpdateService.channel.invokeMethod<void>('openSources');
    } catch (_) {
      if (mounted) {
        setState(() => _message = Strings.of(context).appUpdateInstallerError);
      }
    }
  }

  void _cancel() {
    _service?.close();
    _service = null;
    setState(() {
      _busy = false;
      _progress = null;
      _ready = false;
      _message = Strings.of(context).appUpdateCancelled;
    });
  }

  @override
  void dispose() {
    _service?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final release = _release;
    return HermesPage(
      title: s.appUpdateTitle,
      children: [
        Text(
          'Hermes Console RU',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(s.appUpdateIntro),
        if (_installedVersion != null) ...[
          const SizedBox(height: 12),
          Text(s.appUpdateInstalled(_installedVersion!)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _check,
          icon: const Icon(Icons.system_update_outlined),
          label: Text(s.appUpdateCheck),
        ),
        if (release != null) ...[
          const SizedBox(height: 16),
          Text(
            s.appUpdateAvailable(
              '${release.versionName} (${release.versionCode})',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          // Plain text only: release notes cannot inject links, HTML or commands.
          Text(release.notes.isEmpty ? s.appUpdateNoNotes : release.notes),
          const SizedBox(height: 16),
          if (!_ready)
            FilledButton(
              onPressed: _busy ? null : _download,
              child: Text(s.appUpdateDownload),
            ),
          if (_ready)
            FilledButton(
              onPressed: _busy ? null : _install,
              child: Text(s.appUpdateInstall),
            ),
        ],
        if (_busy) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _progress,
            semanticsLabel: s.appUpdateWorking,
          ),
          const SizedBox(height: 8),
          Text(
            _progress == null
                ? s.appUpdateWorking
                : s.appUpdateProgress((_progress! * 100).round()),
          ),
          if (!_ready)
            TextButton(onPressed: _cancel, child: Text(s.commonCancel)),
        ],
        if (_message != null) ...[
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(_message!)),
        ],
        if (_permission)
          TextButton(
            onPressed: _openSources,
            child: Text(s.appUpdateAllowSource),
          ),
      ],
    );
  }
}
