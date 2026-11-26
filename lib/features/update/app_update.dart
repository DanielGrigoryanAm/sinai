import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sinai/features/chat/widgets/link_text.dart';

/// Whether this build should be updated, as Firebase Remote Config says.
///
/// Parameters (build numbers are the `+N` in pubspec's version):
/// - `min_build`: builds below it must update and can't be used.
/// - `latest_build`: builds below it are offered the update.
/// - `update_url_android`, `update_url_ios`: where "Update" leads.
/// - `update_message`: optional text shown with it.
enum UpdateNeed { none, optional, required }

class UpdateState {
  const UpdateState(this.need, {this.url, this.message});

  final UpdateNeed need;
  final Uri? url;
  final String? message;
}

class AppUpdate extends ValueNotifier<UpdateState> {
  AppUpdate._() : super(const UpdateState(UpdateNeed.none));

  static final instance = AppUpdate._();

  StreamSubscription<RemoteConfigUpdate>? _live;
  int _build = 0;

  /// Reads the config now, and again whenever it changes in the console.
  Future<void> start() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _build = int.tryParse(info.buildNumber) ?? 0;
      final config = FirebaseRemoteConfig.instance;
      await config.setDefaults(const {
        'min_build': 0,
        'latest_build': 0,
        'update_url_android': '',
        'update_url_ios': '',
        'update_message': '',
      });
      await config.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval:
            kDebugMode ? Duration.zero : const Duration(minutes: 30),
      ));
      _apply();
      await config.fetchAndActivate();
      _apply();
      _live ??= config.onConfigUpdated.listen((_) async {
        await config.activate();
        _apply();
      }, onError: (Object e) => debugPrint('Remote config stream: $e'));
    } catch (e) {
      // Offline or Firebase unreachable: the app keeps working as it is.
      debugPrint('Update check failed: $e');
    }
  }

  void _apply() {
    final c = FirebaseRemoteConfig.instance;
    final need = _build < c.getInt('min_build')
        ? UpdateNeed.required
        : _build < c.getInt('latest_build')
            ? UpdateNeed.optional
            : UpdateNeed.none;
    final raw = c.getString(defaultTargetPlatform == TargetPlatform.iOS
        ? 'update_url_ios'
        : 'update_url_android');
    final message = c.getString('update_message').trim();
    value = UpdateState(
      need,
      url: raw.isEmpty ? null : Uri.tryParse(raw),
      message: message.isEmpty ? null : message,
    );
  }
}

/// Wraps the app: a banner offering the update, or a screen that blocks
/// the app until it's updated.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  /// The banner was closed; it comes back on the next launch.
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateState>(
      valueListenable: AppUpdate.instance,
      builder: (context, state, _) {
        if (state.need == UpdateNeed.required) {
          return _UpdateRequired(state: state);
        }
        final banner = state.need == UpdateNeed.optional && !_dismissed;
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              left: 12,
              right: 12,
              bottom: banner ? MediaQuery.paddingOf(context).bottom + 96 : -200,
              child: _UpdateBanner(
                state: state,
                onClose: () => setState(() => _dismissed = true),
              ),
            ),
          ],
        );
      },
    );
  }
}

const _accent = Color(0xFF1D5FA8);

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.state, required this.onClose});

  final UpdateState state;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: _accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'A new version is available',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF1B2030)),
                  ),
                  if (state.message != null)
                    Text(
                      state.message!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7080)),
                    ),
                ],
              ),
            ),
            if (state.url != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: _accent),
                onPressed: () => openLink(state.url!),
                child: const Text('Update',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            // No tooltip: this sits above the navigator, with no overlay.
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded,
                  size: 18, color: Color(0xFF6B7080)),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateRequired extends StatelessWidget {
  const _UpdateRequired({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF5E9),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: _accent.withAlpha(28),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.system_update_rounded,
                    size: 42, color: _accent),
              ),
              const SizedBox(height: 24),
              const Text(
                'Update required',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B2030)),
              ),
              const SizedBox(height: 10),
              Text(
                state.message ??
                    'This version of Sinai no longer works. Update the app '
                        'to keep chatting.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, height: 1.4, color: Color(0xFF6B7080)),
              ),
              const SizedBox(height: 32),
              if (state.url != null)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => openLink(state.url!),
                    child: const Text('Update',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
