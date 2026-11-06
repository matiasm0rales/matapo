import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../main.dart' show AppScope;
import '../player/live_player.dart';

/// Debug only (`--dart-define=MATAPO_STRESS=true` with demo mode): keeps
/// tearing down and recreating live players, the way retries, stalls and
/// screen changes do over hours of real use, to reproduce player crashes in
/// minutes.
class StressScreen extends StatefulWidget {
  const StressScreen({super.key});

  static const enabled = bool.fromEnvironment('MATAPO_STRESS');

  @override
  State<StressScreen> createState() => _StressScreenState();
}

class _StressScreenState extends State<StressScreen> {
  final _random = Random();
  final _generation = List<int>.filled(6, 0);
  late final Timer _timer;
  int _cycles = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      setState(() {
        _cycles++;
        // Recreate one or two random tiles each tick.
        for (var n = 0; n < 1 + _random.nextInt(2); n++) {
          _generation[_random.nextInt(_generation.length)]++;
        }
      });
      if (_cycles % 50 == 0) debugPrint('STRESS: $_cycles cycles');
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cameras = app.cameras;
    if (cameras.isEmpty) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      body: GridView.count(
        crossAxisCount: 3,
        childAspectRatio: 16 / 9,
        children: [
          for (var i = 0; i < _generation.length; i++)
            LiveVideo(
              key: ValueKey('$i-${_generation[i]}'),
              app: app,
              camera: cameras[i % cameras.length],
              compact: true,
              queued: false,
            ),
        ],
      ),
    );
  }
}
