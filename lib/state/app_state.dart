import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/relay_bridge.dart';
import '../api/rtsp_probe.dart';
import '../api/tapo_cloud.dart';
import '../player/stream_queue.dart';
import 'grids.dart';
import 'local_cameras.dart';

export 'local_cameras.dart' show LocalCamera, StreamSource;

enum AuthStage { starting, signedOut, mfa, signedIn }

class Camera {
  Camera(this.raw);
  final Map<String, dynamic> raw;

  String get deviceId => '${raw['deviceId'] ?? ''}';
  String get name => '${raw['alias'] ?? raw['deviceName'] ?? 'Cámara'}'.trim();
  String get model => '${raw['deviceModel'] ?? ''}';
  String get firmware => '${raw['fwVer'] ?? ''}'.split(' ').first;

  /// Account list status; not a live reachability check (the relay can still
  /// work while this reports 0), so it is only used as a hint.
  bool get reportedOnline => raw['status'] == 1;

  bool? privacy;
  bool? ptz;
  String? stateError;
  DateTime? checkedAt;
}

class PendingMfa {
  PendingMfa({
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.processId,
    required this.types,
  });
  final String baseUrl;
  final String username;
  final String password;
  final String processId;
  final List<int> types;
  int? requestedType;
}

class AppState extends ChangeNotifier {
  /// UI test mode (`--dart-define=MATAPO_DEMO=true`): fake cameras, no cloud.
  static const demo = bool.fromEnvironment('MATAPO_DEMO');

  static const _kSession = 'session';
  static const _kTerminal = 'terminal_uuid';
  static const _kLivePreviews = 'live_previews';
  static const _kPtzStep = 'ptz_step';
  static const _kGuideSeen = 'guide_seen';
  static const _kAccount = 'account_hint';
  static const _kGrids = 'grids';
  static const _kActiveGrid = 'active_grid';
  static const _kFavoriteGrid = 'favorite_grid';
  static const _kLocalCameras = 'local_cameras';
  static const _kLocalPasswordPrefix = 'local_pw_';

  /// Camera passwords: Keychain on macOS, encrypted storage on Android.
  /// On macOS the legacy keychain is used, which needs no Keychain Sharing
  /// entitlement (that one requires a provisioning profile, and the app is
  /// signed ad hoc).
  static const _secure = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));

  /// After a local session fails, the camera uses only the cloud this long.
  static const localBlockFor = Duration(minutes: 2);

  /// A successful probe is trusted this long, so a grid doesn't probe the
  /// same camera again for every tile and reconnect.
  static const probeCacheFor = Duration(seconds: 60);

  late SharedPreferences _prefs;
  late SecurityContext _context;
  bool _bootstrapped = false;
  TapoCloud? _client;
  String _baseUrl = loginUrl;
  late final RelayBridge relay = RelayBridge(_resolveForRelay);

  AuthStage stage = AuthStage.starting;
  PendingMfa? pendingMfa;
  List<Camera> cameras = [];
  bool loadingCameras = false;
  String? camerasError;
  String accountHint = '';

  /// False while the app is in the background: all video is stopped.
  bool foreground = true;

  bool livePreviews = true;
  int ptzStep = 10;
  bool guideSeen = false;

  /// User-saved multi-view grids (the built-in "All cameras" is not stored).
  List<GridPreset> savedGrids = [];
  String activeGridId = GridPreset.allCamerasId;

  /// Grid pinned to the top of the home page, if any.
  String? favoriteGridId;

  /// RTSP settings per device id (the passwords are kept apart).
  Map<String, LocalCamera> localCameras = {};
  final Map<String, String> _localPasswords = {};
  final Map<String, DateTime> _localBlockedUntil = {};
  final Map<String, DateTime> _probeOkUntil = {};
  final Map<String, Future<RtspProbeResult>> _probing = {};
  final Map<String, int> _localVersions = {};

  /// Changes whenever a camera's local settings are saved or removed, so
  /// open streams can reconnect with the new settings.
  int localVersion(String deviceId) => _localVersions[deviceId] ?? 0;

  /// How streams check a camera on the home network; tests replace it.
  @visibleForTesting
  RtspProber probe = probeRtsp;

  TapoCloud? get client => _client;

  Future<void> init() async {
    if (!_bootstrapped) {
      _prefs = await SharedPreferences.getInstance();
      final pem = await rootBundle.load('assets/tapo-cloud-roots.pem');
      _context = TapoCloud.buildContext(pem.buffer.asUint8List());
      livePreviews = _prefs.getBool(_kLivePreviews) ?? true;
      ptzStep = _prefs.getInt(_kPtzStep) ?? 10;
      guideSeen = _prefs.getBool(_kGuideSeen) ?? false;
      accountHint = _prefs.getString(_kAccount) ?? '';
      _loadGrids();
      await _loadLocalCameras();
      await Snapshots.instance.init();
      await relay.start();
      _bootstrapped = true;
    }
    camerasError = null;

    if (demo) {
      cameras = [
        for (final (name, model, ptz, privacy) in const [
          ('Living', 'C200', true, false),
          ('Puerta', 'C320WS', false, false),
          ('Jardín', 'C500', true, false),
          ('Cuarto del bebé', 'C210', true, true),
          ('Garaje', 'C110', false, false),
        ])
          Camera({'deviceId': 'demo-$name', 'alias': name, 'deviceModel': model, '_ptz': ptz, '_privacy': privacy}),
      ];
      stage = AuthStage.signedIn;
      notifyListeners();
      for (final c in cameras) {
        unawaited(refreshCameraState(c));
      }
      return;
    }

    final saved = _prefs.getString(_kSession);
    if (saved != null) {
      try {
        final session = jsonDecode(saved) as Map<String, dynamic>;
        final client = _newClient()..token = '${session['token']}';
        final baseUrl = '${session['base_url'] ?? loginUrl}';
        final devices = await client.listCameras(baseUrl);
        _setSignedIn(client, baseUrl, devices);
        return;
      } on TapoException catch (e) {
        if (e.code != null) await _prefs.remove(_kSession);
        // Without a code it was a network problem: keep the session and let
        // the user retry from the sign-in screen.
        camerasError = e.message;
      } catch (_) {
        await _prefs.remove(_kSession);
      }
    }
    stage = AuthStage.signedOut;
    notifyListeners();
  }

  bool get hasSavedSession => _prefs.getString(_kSession) != null;

  Future<void> retrySavedSession() async {
    stage = AuthStage.starting;
    notifyListeners();
    await init();
  }

  TapoCloud _newClient() {
    var terminal = _prefs.getString(_kTerminal);
    if (terminal == null || terminal.isEmpty) {
      terminal = randomUuid().replaceAll('-', '').toUpperCase();
      _prefs.setString(_kTerminal, terminal);
    }
    return TapoCloud(terminalUuid: terminal, context: _context);
  }

  (TapoCloud, String, Map<String, dynamic>)? _resolveForRelay(String deviceId) {
    final client = _client;
    if (client == null) return null;
    for (final c in cameras) {
      if (c.deviceId == deviceId) return (client, _baseUrl, c.raw);
    }
    return null;
  }

  /// Demo mode only: an MPEG-TS URL used instead of the cloud relay, e.g.
  /// `--dart-define=MATAPO_DEMO_STREAM=http://127.0.0.1:8099/live.ts` with
  /// `adb reverse tcp:8099 tcp:8099`.
  static const _demoStream = String.fromEnvironment('MATAPO_DEMO_STREAM');

  String streamUrl(Camera camera, {StreamQuality quality = StreamQuality.hd}) =>
      demo && _demoStream.isNotEmpty ? '$_demoStream?cam=${Uri.encodeComponent(camera.deviceId)}' : relay.urlFor(camera.deviceId, quality: quality);

  // ------------------------------------------------------- Local (RTSP) --

  Future<void> _loadLocalCameras() async {
    try {
      final raw = jsonDecode(_prefs.getString(_kLocalCameras) ?? '{}') as Map;
      localCameras = {
        for (final e in raw.entries) '${e.key}': LocalCamera.fromJson(Map<String, dynamic>.from(e.value as Map)),
      };
    } catch (_) {
      localCameras = {};
    }
    for (final id in localCameras.keys) {
      try {
        final pw = await _secure.read(key: '$_kLocalPasswordPrefix$id');
        if (pw != null) _localPasswords[id] = pw;
      } catch (e) {
        debugPrint('Matapo: could not read a camera password: $e');
      }
    }
  }

  Future<void> _saveLocalCameras() => _prefs.setString(
        _kLocalCameras,
        jsonEncode({for (final e in localCameras.entries) e.key: e.value.toJson()}),
      );

  LocalCamera? localCameraFor(Camera camera) => localCameras[camera.deviceId];

  /// True when the camera has local settings and a stored password.
  bool hasLocal(Camera camera) =>
      localCameras.containsKey(camera.deviceId) && _localPasswords.containsKey(camera.deviceId);

  /// Saves (or with a null [cam], removes) a camera's local settings. A null
  /// [password] with a non-null [cam] keeps the stored password.
  Future<void> setLocalCamera(String deviceId, LocalCamera? cam, String? password) async {
    _localVersions[deviceId] = localVersion(deviceId) + 1;
    _localBlockedUntil.remove(deviceId);
    _probeOkUntil.remove(deviceId);
    final key = '$_kLocalPasswordPrefix$deviceId';
    if (cam == null) {
      localCameras.remove(deviceId);
      _localPasswords.remove(deviceId);
      await _saveLocalCameras();
      try {
        await _secure.delete(key: key);
      } catch (_) {}
    } else {
      localCameras[deviceId] = cam;
      await _saveLocalCameras();
      if (password != null) {
        _localPasswords[deviceId] = password;
        await _secure.write(key: key, value: password);
      }
    }
    notifyListeners();
  }

  /// "Probar": checks [cam] with [password], or the stored password when
  /// [password] is null or empty.
  Future<RtspProbeResult> testLocal(String deviceId, LocalCamera cam, String? password) {
    final pw = (password == null || password.isEmpty) ? _localPasswords[deviceId] : password;
    if (pw == null) return Future.value(const RtspProbeResult(RtspProbeStatus.badCredentials));
    return probe(cam, pw, timeout: const Duration(seconds: 4));
  }

  bool isLocalBlocked(String deviceId) {
    final until = _localBlockedUntil[deviceId];
    return until != null && DateTime.now().isBefore(until);
  }

  /// A local session failed: use the cloud for [localBlockFor].
  void blockLocal(String deviceId) {
    _localBlockedUntil[deviceId] = DateTime.now().add(localBlockFor);
    _probeOkUntil.remove(deviceId);
  }

  @visibleForTesting
  void debugSetLocal(String deviceId, LocalCamera cam, String password) {
    localCameras[deviceId] = cam;
    _localPasswords[deviceId] = password;
  }

  /// Where the next stream for [camera] should come from: the camera itself
  /// over RTSP when it is set up, not blocked and answers quickly; otherwise
  /// the cloud relay (or the demo stream in demo mode).
  Future<(StreamSource, String)> pickSource(Camera camera, StreamQuality quality) async {
    final id = camera.deviceId;
    final cam = localCameras[id];
    final password = _localPasswords[id];
    if (cam != null && password != null && !isLocalBlocked(id)) {
      final okUntil = _probeOkUntil[id];
      var ok = okUntil != null && DateTime.now().isBefore(okUntil);
      if (!ok) {
        final result = await (_probing[id] ??= probe(cam, password).whenComplete(() {
          _probing.remove(id);
        }));
        ok = result.ok;
        if (ok) {
          _probeOkUntil[id] = DateTime.now().add(probeCacheFor);
        } else {
          // Away from home: don't make every reconnect wait for the probe.
          debugPrint('Matapo: local video for $id unavailable ($result), using the cloud');
          blockLocal(id);
        }
      }
      // The settings may have changed while probing.
      if (ok && localCameras[id] == cam && _localPasswords[id] == password) {
        return (StreamSource.local, rtspUrl(cam, password, quality));
      }
    }
    return (StreamSource.cloud, streamUrl(camera, quality: quality));
  }

  // ---------------------------------------------------------------- Auth --

  /// Returns true when a verification step is needed.
  Future<bool> login(String username, String password) async {
    username = username.trim();
    if (username.isEmpty || password.isEmpty) {
      throw TapoException('Ingresá tu correo y tu contraseña de Tapo');
    }
    final client = _newClient();
    final result = await client.login(username, password);
    final processId = result.mfaProcessId;
    accountHint = username;
    await _prefs.setString(_kAccount, username);
    if (processId != null && processId.isNotEmpty) {
      _client?.close();
      _client = client;
      pendingMfa = PendingMfa(
        baseUrl: result.baseUrl,
        username: username,
        password: password,
        processId: processId,
        types: result.mfaTypes,
      );
      stage = AuthStage.mfa;
      notifyListeners();
      return true;
    }
    await _finishLogin(client, result.baseUrl, result.result);
    return false;
  }

  Future<void> requestMfa(int type) async {
    final pending = pendingMfa;
    final client = _client;
    if (pending == null || client == null) throw TapoException('Volvé a iniciar sesión');
    await client.requestMfa(pending.baseUrl, pending.username, pending.password, type);
    pending.requestedType = type;
    notifyListeners();
  }

  Future<void> verifyMfa(String code) async {
    final pending = pendingMfa;
    final client = _client;
    if (pending == null || client == null) throw TapoException('Volvé a iniciar sesión');
    final type = pending.requestedType;
    if (type == null) throw TapoException('Primero pedí un código de verificación');
    code = code.trim();
    if (code.isEmpty) throw TapoException('Ingresá el código de verificación');
    final result = await client.verifyMfa(pending.baseUrl, pending.username, code, pending.processId, type);
    await _finishLogin(client, pending.baseUrl, result);
  }

  void cancelMfa() {
    pendingMfa = null;
    stage = AuthStage.signedOut;
    notifyListeners();
  }

  Future<void> _finishLogin(TapoCloud client, String baseUrl, Map<String, dynamic> result) async {
    final token = result['token'];
    if (token == null || '$token'.isEmpty) {
      throw TapoException('La nube no devolvió una sesión');
    }
    client.token = '$token';
    final devices = await client.listCameras(baseUrl);
    // Only the session token is stored; the password never is.
    await _prefs.setString(
      _kSession,
      jsonEncode({
        'base_url': baseUrl,
        'token': '$token',
        'refreshToken': result['refreshToken'],
        'saved_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }),
    );
    pendingMfa = null;
    _setSignedIn(client, baseUrl, devices);
  }

  void _setSignedIn(TapoCloud client, String baseUrl, List<Map<String, dynamic>> devices) {
    if (!identical(_client, client)) _client?.close();
    _client = client;
    _baseUrl = baseUrl;
    cameras = devices.map(Camera.new).toList();
    camerasError = null;
    stage = AuthStage.signedIn;
    notifyListeners();
    for (final camera in cameras) {
      unawaited(refreshCameraState(camera));
    }
  }

  Future<void> logout() async {
    _client?.close();
    _client = null;
    cameras = [];
    pendingMfa = null;
    await _prefs.remove(_kSession);
    // Forget the terminal identity too so the next sign-in asks for MFA.
    await _prefs.remove(_kTerminal);
    // Camera accounts belong to this sign-in too.
    for (final id in {...localCameras.keys, ..._localPasswords.keys}) {
      try {
        await _secure.delete(key: '$_kLocalPasswordPrefix$id');
      } catch (_) {}
    }
    localCameras = {};
    _localPasswords.clear();
    _localBlockedUntil.clear();
    _probeOkUntil.clear();
    await _prefs.remove(_kLocalCameras);
    stage = AuthStage.signedOut;
    notifyListeners();
  }

  void _handleAuthFailure(Object error) {
    if (error is TapoException && error.isAuthError) {
      unawaited(logout());
    }
  }

  // ------------------------------------------------------------- Cameras --

  Future<void> refreshCameras() async {
    if (demo) return;
    final client = _client;
    if (client == null) return;
    loadingCameras = true;
    camerasError = null;
    notifyListeners();
    try {
      final devices = await client.listCameras(_baseUrl);
      final previous = {for (final c in cameras) c.deviceId: c};
      cameras = devices.map((d) {
        final camera = Camera(d);
        final old = previous[camera.deviceId];
        camera.privacy = old?.privacy;
        camera.ptz = old?.ptz;
        return camera;
      }).toList();
      for (final camera in cameras) {
        unawaited(refreshCameraState(camera, force: true));
      }
    } catch (e) {
      camerasError = e.toString();
      _handleAuthFailure(e);
    } finally {
      loadingCameras = false;
      notifyListeners();
    }
  }

  Future<void> refreshCameraState(Camera camera, {bool force = false}) async {
    if (demo) {
      camera.ptz = camera.raw['_ptz'] == true;
      camera.privacy ??= camera.raw['_privacy'] == true;
      notifyListeners();
      return;
    }
    final client = _client;
    if (client == null) return;
    final checked = camera.checkedAt;
    if (!force && checked != null && DateTime.now().difference(checked) < const Duration(seconds: 10)) {
      return;
    }
    camera.checkedAt = DateTime.now();
    try {
      camera.privacy = await client.getPrivacyMode(_baseUrl, camera.deviceId);
      camera.stateError = null;
    } catch (e) {
      camera.stateError = e.toString();
      _handleAuthFailure(e);
    }
    try {
      camera.ptz ??= await client.ptzSupported(_baseUrl, camera.deviceId);
    } catch (_) {
      camera.ptz ??= null;
    }
    notifyListeners();
  }

  Future<void> setPrivacy(Camera camera, bool enabled) async {
    if (demo) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      camera.privacy = enabled;
      notifyListeners();
      return;
    }
    final client = _client;
    if (client == null) return;
    camera.privacy = await client.setPrivacyMode(_baseUrl, camera.deviceId, enabled);
    camera.checkedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> move(Camera camera, int x, int y) async {
    if (demo) return Future<void>.delayed(const Duration(milliseconds: 300));
    final client = _client;
    if (client == null) return;
    await client.moveMotor(_baseUrl, camera.deviceId, x, y);
  }

  void setForeground(bool value) {
    if (foreground == value) return;
    foreground = value;
    notifyListeners();
  }

  // ------------------------------------------------------------ Settings --

  Future<void> setLivePreviews(bool value) async {
    livePreviews = value;
    await _prefs.setBool(_kLivePreviews, value);
    notifyListeners();
  }

  Future<void> setPtzStep(int value) async {
    ptzStep = value;
    await _prefs.setInt(_kPtzStep, value);
    notifyListeners();
  }

  Future<void> markGuideSeen() async {
    guideSeen = true;
    await _prefs.setBool(_kGuideSeen, true);
    notifyListeners();
  }

  // ---------------------------------------------------------- Multi-view --

  void _loadGrids() {
    try {
      final raw = jsonDecode(_prefs.getString(_kGrids) ?? '[]') as List;
      savedGrids = [for (final g in raw) GridPreset.fromJson(Map<String, dynamic>.from(g as Map))];
    } catch (_) {
      savedGrids = [];
    }
    activeGridId = _prefs.getString(_kActiveGrid) ?? GridPreset.allCamerasId;
    favoriteGridId = _prefs.getString(_kFavoriteGrid);
  }

  Future<void> _saveGrids() =>
      _prefs.setString(_kGrids, jsonEncode([for (final g in savedGrids) g.toJson()]));

  /// Built-in grid showing every camera (first nine) in a fitting layout.
  GridPreset get allCamerasGrid {
    final layout = GridLayout.fitting(cameras.length);
    return GridPreset(
      id: GridPreset.allCamerasId,
      name: 'Todas las cámaras',
      layout: layout,
      slots: [for (final c in cameras.take(layout.slots)) c.deviceId],
    );
  }

  /// All grids in switching order: "All cameras" first, then saved ones.
  List<GridPreset> get grids => [allCamerasGrid, ...savedGrids];

  GridPreset gridById(String id) => grids.firstWhere((g) => g.id == id, orElse: () => allCamerasGrid);

  Camera? cameraById(String? deviceId) {
    if (deviceId == null) return null;
    for (final c in cameras) {
      if (c.deviceId == deviceId) return c;
    }
    return null;
  }

  int cameraIndex(String deviceId) => cameras.indexWhere((c) => c.deviceId == deviceId);

  GridPreset? get favoriteGrid {
    final id = favoriteGridId;
    if (id == null) return null;
    for (final g in grids) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Pins [id] to the home page, or unpins with null.
  Future<void> setFavoriteGrid(String? id) async {
    favoriteGridId = id;
    if (id == null) {
      await _prefs.remove(_kFavoriteGrid);
    } else {
      await _prefs.setString(_kFavoriteGrid, id);
    }
    notifyListeners();
  }

  Future<void> setActiveGrid(String id) async {
    activeGridId = id;
    await _prefs.setString(_kActiveGrid, id);
    notifyListeners();
  }

  /// Inserts or replaces a saved grid; returns the stored preset.
  Future<GridPreset> saveGrid(GridPreset grid) async {
    final stored = grid.id.isEmpty
        ? GridPreset(
            id: 'g${DateTime.now().millisecondsSinceEpoch}',
            name: grid.name,
            layout: grid.layout,
            slots: grid.slots,
          )
        : grid;
    final i = savedGrids.indexWhere((g) => g.id == stored.id);
    if (i >= 0) {
      savedGrids[i] = stored;
    } else {
      savedGrids.add(stored);
    }
    await _saveGrids();
    notifyListeners();
    return stored;
  }

  Future<void> deleteGrid(String id) async {
    savedGrids.removeWhere((g) => g.id == id);
    if (favoriteGridId == id) {
      favoriteGridId = null;
      await _prefs.remove(_kFavoriteGrid);
    }
    if (activeGridId == id) {
      activeGridId = GridPreset.allCamerasId;
      await _prefs.setString(_kActiveGrid, activeGridId);
    }
    await _saveGrids();
    notifyListeners();
  }

  String get regionHost => Uri.tryParse(_baseUrl)?.host ?? _baseUrl;
}
