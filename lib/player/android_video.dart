import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

/// Routes native player events (see LivePlayer.kt) to their view.
class _PlayerEvents {
  _PlayerEvents._() {
    const MethodChannel('topo/player').setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      _listeners[(args['id'] as num).toInt()]?.call(args);
    });
  }
  static final instance = _PlayerEvents._();
  final _listeners = <int, void Function(Map<String, dynamic>)>{};
}

/// The native ExoPlayer view on Android, embedded with hybrid composition.
/// One view is one stream session: a new key means a new connection.
class AndroidVideo extends StatelessWidget {
  const AndroidVideo({super.key, required this.url, required this.snapshotPath, required this.onEvent});
  final String url;
  final String? snapshotPath;
  final void Function(Map<String, dynamic>) onEvent;

  static const _viewType = 'topo/live-video';

  @override
  Widget build(BuildContext context) {
    // The native view never takes focus; keep it out of D-pad traversal.
    return ExcludeFocus(
      child: PlatformViewLink(
        viewType: _viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const {},
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        ),
        onCreatePlatformView: (params) {
          _PlayerEvents.instance._listeners[params.id] = onEvent;
          final controller = PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: _viewType,
            layoutDirection: TextDirection.ltr,
            creationParams: {'url': url, 'snapshot': snapshotPath},
            creationParamsCodec: const StandardMessageCodec(),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
          return controller;
        },
      ),
    );
  }
}
