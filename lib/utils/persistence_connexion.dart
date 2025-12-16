// persistence_connexion.dart - VERSION CORRIGÉE

import 'dart:async';
import 'dart:io';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:claude_iot/services/services.commun.dart' as commun;
import 'package:claude_iot/services/services.bluetooth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

enum CommunicationMode { wifi, bluetooth, none }

// CLASSE COMMUNICATION SERVICE AJOUTÉE ICI
class CommunicationService {
  final commun.WiFiCommunicationManager wifiManager = commun.WiFiCommunicationManager();
  final BluetoothCommunicationManager bluetoothManager = BluetoothCommunicationManager();
  
  CommunicationMode _activeMode = CommunicationMode.none;

  CommunicationMode getActiveMode() => _activeMode;

  void initialize() {
    wifiManager.initialize();
    bluetoothManager.initialize();
  }

  void dispose() {
    wifiManager.dispose();
    bluetoothManager.dispose();
  }

  void setActiveMode(CommunicationMode mode) {
    _activeMode = mode;
  }

  void disconnectAll() {
    wifiManager.disconnectAllWifiConnections();
    bluetoothManager.disconnectAllBluetoothConnections();
  }
  void sendWebSocketMessage(String message) {
    wifiManager.sendWebSocketMessage(message);
  }

  Stream<bool> get globalConnectionStateStream {
    return MergeStream([
      wifiManager.isWebSocketConnected,
      bluetoothManager.connectionStateStream,
    ]);
  }

  Stream<String> get globalReceivedDataStream {
    return MergeStream([
      wifiManager.webSocketMessages,
      bluetoothManager.receivedDataStream,
    ]);
  }

  Stream<bool> get bluetoothEnabledStream => bluetoothManager.bluetoothEnabledStream;

  Future<bool> isWifiConnected() async {
  try {
    final connectivity = await Connectivity().checkConnectivity();
    return connectivity.contains(ConnectivityResult.wifi);
  } catch (e) {
    return false;
  }
}

  // Méthodes Bluetooth
  Future<bool> isBluetoothEnabled() async {
    return await bluetoothManager.isBluetoothEnabled();
  }

  Future<void> setBluetoothEnabled(bool enabled) async {
    await bluetoothManager.setBluetoothEnabled(enabled);
  }

  Future<List<BluetoothDevice>> scanBluetoothDevices({
    required BluetoothProtocol protocol,
    int duration = 10,
  }) async {
    return await bluetoothManager.scanDevices(
      protocol: protocol,
      duration: duration,
    );
  }

  Future<({bool success, String message})> sendHttpCommand({
    required String ip,
    required int port,
    required String command,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return wifiManager.sendHttpCommand(
      ip: ip, port: port, command: command, timeout: timeout,
    );
  }

  Future<bool> connectWebSocket(String ip, {int port = 81}) {
    return wifiManager.connectWebSocket(ip, port: port);
  }

  Stream<bool> get isWebSocketConnected => wifiManager.isWebSocketConnected;

  Future<void> sendBluetoothCommand(String command) {
  return bluetoothManager.sendCommand(command);
}

  Future<void> connectBluetoothDevice(BluetoothDevice device) {
    return bluetoothManager.connectToDevice(device);
  }
}

class PersistenceConnexion {
  final CommunicationService _communicationService;
  final Function(String) onLogMessage;
  final Function(bool) onConnectionStatusChanged;
  final Function() onReconnectStarted;
  final Function(String, int, commun.MicrocontrollerType?) onReconnectSuccess;
  final Function(BluetoothDevice) onBluetoothReconnectSuccess;
  final Function(String) onReconnectFailed;

  Timer? _reconnectTimer;
  Timer? _connectionMonitorTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectInterval = Duration(seconds: 5);
  static const Duration _connectionCheckInterval = Duration(seconds: 15);

  String? _lastConnectedIP;
  int? _lastConnectedPort;
  commun.WiFiProtocol? _lastWifiProtocol;
  String? _lastBluetoothDeviceId;
  String? _lastBluetoothDeviceName;
  BluetoothProtocol? _lastBluetoothProtocol;
  bool? _lastBluetoothDeviceIsBle;
  String? _lastConnectionMode;
  bool _autoConnectEnabled = true;
  commun.MicrocontrollerType? _lastDetectedMicrocontrollerType;
  String? _lastMicrocontrollerSignature;
  StreamSubscription? _connectivitySubscription;
  bool _isMonitoring = false;

  String? get lastConnectedIP => _lastConnectedIP;
  int? get lastConnectedPort => _lastConnectedPort;
  commun.WiFiProtocol? get lastWifiProtocol => _lastWifiProtocol;
  String? get lastBluetoothDeviceId => _lastBluetoothDeviceId;
  String? get lastBluetoothDeviceName => _lastBluetoothDeviceName;
  BluetoothProtocol? get lastBluetoothProtocol => _lastBluetoothProtocol;
  String? get lastConnectionMode => _lastConnectionMode;
  commun.MicrocontrollerType? get lastDetectedMicrocontrollerType => _lastDetectedMicrocontrollerType;
  bool get isMonitoring => _isMonitoring;
  bool get isReconnecting => _reconnectTimer != null;
  int get reconnectAttempts => _reconnectAttempts;
  bool get autoConnectEnabled => _autoConnectEnabled;

  PersistenceConnexion({
    required this.onLogMessage,
    required this.onConnectionStatusChanged,
    required this.onReconnectStarted,
    required this.onReconnectSuccess,
    required this.onBluetoothReconnectSuccess,
    required this.onReconnectFailed,
    required CommunicationService communicationService,
  }) : _communicationService = communicationService;
  
  Future<void> initialize() async {
    await _loadConnectionSettings();
    _setupConnectivityListener();
    onLogMessage('✅ Service de persistance initialisé');
  }

  Future<void> _loadConnectionSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastConnectionMode = prefs.getString('lastConnectionMode');
      _lastConnectedIP = prefs.getString('lastConnectedIP');
      _lastConnectedPort = prefs.getInt('lastConnectedPort');
      _lastWifiProtocol = _protocolFromString(prefs.getString('lastWifiProtocol'));
      _lastBluetoothDeviceId = prefs.getString('lastBluetoothDeviceId');
      _lastBluetoothDeviceName = prefs.getString('lastBluetoothDeviceName');
      _lastBluetoothProtocol = _bluetoothProtocolFromString(prefs.getString('lastBluetoothProtocol'));
      _lastBluetoothDeviceIsBle = prefs.getBool('lastBluetoothDeviceIsBle');
      _autoConnectEnabled = prefs.getBool('autoConnectEnabled') ?? true;
      
      final typeString = prefs.getString('lastMicrocontrollerType');
      _lastDetectedMicrocontrollerType = _microcontrollerTypeFromString(typeString);
      _lastMicrocontrollerSignature = prefs.getString('lastMicrocontrollerSignature');

      onLogMessage('📂 Paramètres chargés: $_lastConnectionMode');
    } catch (e) {
      onLogMessage('❌ Erreur chargement paramètres: $e');
    }
  }

  commun.WiFiProtocol _protocolFromString(String? protocol) {
    if (protocol == 'WiFiProtocol.websocket') return commun.WiFiProtocol.websocket;
    return commun.WiFiProtocol.http;
  }

  BluetoothProtocol _bluetoothProtocolFromString(String? protocol) {
    if (protocol == 'BluetoothProtocol.ble') return BluetoothProtocol.ble;
    return BluetoothProtocol.classic;
  }

  commun.MicrocontrollerType? _microcontrollerTypeFromString(String? type) {
    if (type == 'commun.MicrocontrollerType.direct') return commun.MicrocontrollerType.direct;
    if (type == 'commun.MicrocontrollerType.parameter') return commun.MicrocontrollerType.parameter;
    if (type == 'commun.MicrocontrollerType.auto') return commun.MicrocontrollerType.auto;
    return null;
  }

  Map<String, dynamic> getConnectionStatus() {
    return {
      'lastConnectionMode': _lastConnectionMode,
      'autoConnectEnabled': _autoConnectEnabled,
      'isReconnecting': isReconnecting,
      'reconnectAttempts': _reconnectAttempts,
      'wifiSettings': {
        'ip': _lastConnectedIP,
        'port': _lastConnectedPort,
        'protocol': _lastWifiProtocol?.toString(),
      },
      'bluetoothSettings': {
        'deviceId': _lastBluetoothDeviceId,
        'deviceName': _lastBluetoothDeviceName,
        'protocol': _lastBluetoothProtocol?.toString(),
      },
    };
  }

  String? _microcontrollerTypeToString(commun.MicrocontrollerType? type) {
    if (type == commun.MicrocontrollerType.direct) return 'commun.MicrocontrollerType.direct';
    if (type == commun.MicrocontrollerType.parameter) return 'commun.MicrocontrollerType.parameter';
    if (type == commun.MicrocontrollerType.auto) return 'commun.MicrocontrollerType.auto';
    return null;
  }

  Future<void> clearConnectionHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastConnectionMode');
    await prefs.remove('lastConnectedIP');
    await prefs.remove('lastConnectedPort');
    await prefs.remove('lastWifiProtocol');
    await prefs.remove('lastBluetoothDeviceId');
    await prefs.remove('lastBluetoothDeviceName');
    await prefs.remove('lastBluetoothProtocol');
    await prefs.remove('lastBluetoothDeviceIsBle');
    await prefs.remove('lastMicrocontrollerType');
    await prefs.remove('lastMicrocontrollerSignature');
    await prefs.remove('autoConnectEnabled');
    await prefs.remove('wasConnected');

    // Réinitialiser les variables en mémoire
    _lastConnectionMode = null;
    _lastConnectedIP = null;
    _lastConnectedPort = null;
    _lastWifiProtocol = null;
    _lastBluetoothDeviceId = null;
    _lastBluetoothDeviceName = null;
    _lastBluetoothProtocol = null;
    _lastBluetoothDeviceIsBle = null;
    _lastDetectedMicrocontrollerType = null;
    _lastMicrocontrollerSignature = null;
    _autoConnectEnabled = true;

    onLogMessage('🗑️ Historique de connexion effacé');
  }

  Future<void> _saveConnectionSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_lastConnectionMode != null) await prefs.setString('lastConnectionMode', _lastConnectionMode!);
      if (_lastConnectedIP != null) await prefs.setString('lastConnectedIP', _lastConnectedIP!);
      if (_lastConnectedPort != null) await prefs.setInt('lastConnectedPort', _lastConnectedPort!);
      if (_lastWifiProtocol != null) await prefs.setString('lastWifiProtocol', _lastWifiProtocol.toString());
      if (_lastBluetoothDeviceId != null) await prefs.setString('lastBluetoothDeviceId', _lastBluetoothDeviceId!);
      if (_lastBluetoothDeviceName != null) await prefs.setString('lastBluetoothDeviceName', _lastBluetoothDeviceName!);
      if (_lastBluetoothProtocol != null) await prefs.setString('lastBluetoothProtocol', _lastBluetoothProtocol.toString());
      if (_lastBluetoothDeviceIsBle != null) await prefs.setBool('lastBluetoothDeviceIsBle', _lastBluetoothDeviceIsBle!);
      if (_lastDetectedMicrocontrollerType != null) await prefs.setString('lastMicrocontrollerType', _microcontrollerTypeToString(_lastDetectedMicrocontrollerType)!);
      if (_lastMicrocontrollerSignature != null) await prefs.setString('lastMicrocontrollerSignature', _lastMicrocontrollerSignature!);
      
      await prefs.setBool('autoConnectEnabled', _autoConnectEnabled);
      await prefs.setBool('wasConnected', true);
    } catch (e) {
      onLogMessage('❌ Erreur sauvegarde paramètres: $e');
    }
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final isNetworkAvailable = results.isNotEmpty && results.any((result) => result == ConnectivityResult.wifi || result == ConnectivityResult.mobile);

      if (!isNetworkAvailable) {
        onLogMessage('📡 Réseau perdu');
        if (_lastConnectionMode == 'wifi' && _isConnected()) _handleConnectionLost();
      } else {
        onLogMessage('📡 Réseau disponible');
        Future.delayed(const Duration(seconds: 3), () {
          if (_autoConnectEnabled && !_isConnected() && _lastConnectionMode != null) {
            onLogMessage('🔄 Tentative reconnexion automatique...');
            _scheduleReconnect();
          }
        });
      }
    });
  }

  bool _isConnected() {
    final activeMode = _communicationService.getActiveMode();
    if (activeMode == CommunicationMode.wifi) {
      return _communicationService.wifiManager.getActiveProtocol() != commun.WiFiProtocol.none;
    } else if (activeMode == CommunicationMode.bluetooth) {
      try {
        return _communicationService.bluetoothManager.connectionStateStream.isBroadcast;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  void _startConnectionMonitoring() {
    _stopConnectionMonitoring();
    _isMonitoring = true;
    _connectionMonitorTimer = Timer.periodic(_connectionCheckInterval, (timer) async {
      if (_lastConnectionMode == 'wifi' && _isConnected()) {
        final isStillConnected = await _verifyWifiConnection(_lastConnectedIP!, _lastConnectedPort!, _lastWifiProtocol!);
        if (!isStillConnected) {
          onLogMessage('⚠️ Connexion perdue lors de la surveillance');
          _handleConnectionLost();
        }
      } else {
        _stopConnectionMonitoring();
      }
    });
  }

  void _stopConnectionMonitoring() {
    _connectionMonitorTimer?.cancel();
    _connectionMonitorTimer = null;
    _isMonitoring = false;
  }

  Future<bool> _verifyWifiConnection(String ip, int port, commun.WiFiProtocol protocol) async {
    try {
      if (protocol == commun.WiFiProtocol.http) {
        try {
          final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
          socket.destroy();
        } catch (e) {
          return false;
        }

        final result = await _communicationService.sendHttpCommand(ip: ip, port: port, command: 'status')
            .timeout(const Duration(seconds: 5), onTimeout: () => (success: false, message: 'Timeout'));
        
        _analyzeMicrocontrollerResponse(result.message);
        return result.success || result.message.contains('200') || result.message.contains('OK');
        
      } else if (protocol == commun.WiFiProtocol.websocket) {
        final connected = await _communicationService.isWebSocketConnected.first.timeout(const Duration(seconds: 3), onTimeout: () => false);
        return connected;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void _analyzeMicrocontrollerResponse(String response) {
    if (response.contains('/cmd?c=') || response.contains('WebServer')) {
      _lastDetectedMicrocontrollerType = commun.MicrocontrollerType.parameter;
      _lastMicrocontrollerSignature = 'WebServer.h';
    } else if (response.contains('WiFiServer') || response.contains('direct')) {
      _lastDetectedMicrocontrollerType = commun.MicrocontrollerType.direct;
      _lastMicrocontrollerSignature = 'WiFi.h';
    } else if (response.contains('ESP32') || response.contains('Arduino')) {
      _lastDetectedMicrocontrollerType = commun.MicrocontrollerType.direct;
      _lastMicrocontrollerSignature = 'ESP32/Arduino';
    }
  }

  Future<bool> _verifyBluetoothConnection(BluetoothDevice device) async {
  try {
    // Utilisez la nouvelle méthode isConnected()
    return _communicationService.bluetoothManager.isConnected();
  } catch (e) {
    return false;
  }
}

  Future<bool> connectWifi(String ip, int port, commun.WiFiProtocol protocol, {commun.MicrocontrollerType? forcedType}) async {
    try {
      onLogMessage('🔄 Connexion Wi-Fi à $ip:$port ($protocol)');
      
      final connectivity = await Connectivity().checkConnectivity();
      final hasNetwork = connectivity.any((result) => result == ConnectivityResult.wifi || result == ConnectivityResult.mobile);
      if (!hasNetwork) {
        onLogMessage('❌ Aucune connexion réseau disponible');
        return false;
      }

      _communicationService.disconnectAll();
      await Future.delayed(const Duration(milliseconds: 500));
      
      _communicationService.setActiveMode(CommunicationMode.wifi);
      _communicationService.wifiManager.setActiveProtocol(protocol);

      if (forcedType != null) {
        _communicationService.wifiManager.setMicrocontrollerType(forcedType);
        onLogMessage('🔧 Type microcontrôleur forcé: $forcedType');
      }

      bool connected = false;
      if (protocol == commun.WiFiProtocol.http) {
        connected = await _verifyWifiConnection(ip, port, protocol);
        if (connected) {
          final testResult = await _communicationService.sendHttpCommand(ip: ip, port: port, command: 'info').timeout(const Duration(seconds: 3));
          connected = testResult.success;
          _analyzeMicrocontrollerResponse(testResult.message);
        }
      } else if (protocol == commun.WiFiProtocol.websocket) {
        connected = await _communicationService.connectWebSocket(ip, port: port);
      }

      if (connected) {
        _lastConnectionMode = 'wifi';
        _lastConnectedIP = ip;
        _lastConnectedPort = port;
        _lastWifiProtocol = protocol;
        
        await _saveConnectionSettings();
        _resetReconnectAttempts();
        onConnectionStatusChanged(true);
        onLogMessage('✅ Connexion Wi-Fi ÉTABLIE à $ip:$port');
        _startConnectionMonitoring();
        return true;
      } else {
        onLogMessage('❌ Échec connexion Wi-Fi');
        onConnectionStatusChanged(false);
        return false;
      }
    } catch (e) {
      onLogMessage('❌ ERREUR connexion Wi-Fi: ${e.toString()}');
      onConnectionStatusChanged(false);
      return false;
    }
  }

  // Dans la classe PersistenceConnexion, ajoutez cette méthode pour vérifier l'état Wi-Fi
Future<bool> checkWifiConnectivity() async {
  try {
    final connectivity = await Connectivity().checkConnectivity();
    return connectivity.contains(ConnectivityResult.wifi);
  } catch (e) {
    return false;
  }
}

  Future<bool> connectBluetooth(BluetoothDevice device, BluetoothProtocol protocol) async {
    try {
      onLogMessage('🔄 Connexion Bluetooth à ${device.name}');
      
      _communicationService.setActiveMode(CommunicationMode.bluetooth);
      _communicationService.bluetoothManager.setActiveProtocol(protocol);
      await _communicationService.connectBluetoothDevice(device);

      bool isActuallyConnected = await _verifyBluetoothConnection(device);
      if (isActuallyConnected) {
        _lastConnectionMode = 'bluetooth';
        _lastBluetoothDeviceId = device.id;
        _lastBluetoothDeviceName = device.name;
        _lastBluetoothProtocol = protocol;
        _lastBluetoothDeviceIsBle = device.isBle;
        
        await _saveConnectionSettings();
        _resetReconnectAttempts();
        onConnectionStatusChanged(true);
        onLogMessage('✅ Connexion Bluetooth réussie');
        return true;
      } else {
        onLogMessage('❌ Connexion Bluetooth échouée');
        _communicationService.disconnectAll();
        return false;
      }
    } catch (e) {
      onLogMessage('❌ Erreur connexion Bluetooth: ${e.toString()}');
      return false;
    }
  }

  Future<bool> attemptAutoReconnect() async {
    if (_lastConnectionMode == null || !_autoConnectEnabled) return false;

    onReconnectStarted();
    onLogMessage('🔄 Reconnexion automatique...');
    bool success = false;
    
    try {
      if (_lastConnectionMode == 'wifi' && _lastConnectedIP != null && _lastConnectedPort != null) {
        final protocol = _lastWifiProtocol ?? commun.WiFiProtocol.http;
        if (_lastDetectedMicrocontrollerType != null) {
          _communicationService.wifiManager.setMicrocontrollerType(_lastDetectedMicrocontrollerType!);
        }
        success = await connectWifi(_lastConnectedIP!, _lastConnectedPort!, protocol).timeout(const Duration(seconds: 10), onTimeout: () => false);
      } else if (_lastConnectionMode == 'bluetooth' && _lastBluetoothDeviceId != null) {
        final device = BluetoothDevice(id: _lastBluetoothDeviceId!, name: _lastBluetoothDeviceName ?? 'Appareil inconnu', isBle: _lastBluetoothDeviceIsBle ?? false);
        final protocol = _lastBluetoothProtocol ?? BluetoothProtocol.classic;
        success = await connectBluetooth(device, protocol).timeout(const Duration(seconds: 15), onTimeout: () => false);
      }
    } catch (e) {
      onLogMessage('❌ Erreur reconnexion automatique: ${e.toString()}');
      success = false;
    }
    
    if (!success) onReconnectFailed('Appareil non joignable');
    return success;
  }


  void startAutoReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts || !_autoConnectEnabled) {
      onReconnectFailed('Nombre maximum de tentatives atteint');
      return;
    }

    _reconnectTimer = Timer.periodic(_reconnectInterval, (timer) async {
      _reconnectAttempts++;
      onLogMessage('🔄 Tentative $_reconnectAttempts/$_maxReconnectAttempts');
      final success = await attemptAutoReconnect();
      if (success) {
        _resetReconnectAttempts();
        timer.cancel();
        if (_lastConnectionMode == 'wifi') {
          onReconnectSuccess(_lastConnectedIP!, _lastConnectedPort!, _lastDetectedMicrocontrollerType);
        } else if (_lastConnectionMode == 'bluetooth') {
          final device = BluetoothDevice(id: _lastBluetoothDeviceId!, name: _lastBluetoothDeviceName!, isBle: _lastBluetoothDeviceIsBle ?? false);
          onBluetoothReconnectSuccess(device);
        }
      } else if (_reconnectAttempts >= _maxReconnectAttempts) {
        timer.cancel();
        onReconnectFailed('Impossible de se reconnecter après $_maxReconnectAttempts tentatives');
      }
    });
  }

  void _handleConnectionLost() {
    onConnectionStatusChanged(false);
    onLogMessage('🔌 Connexion perdue');
    if (_autoConnectEnabled) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_autoConnectEnabled || _reconnectTimer != null) return;
    onLogMessage('⏰ Reconnexion dans 3 secondes...');
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_isConnected() && _autoConnectEnabled) startAutoReconnect();
    });
  }

  void _resetReconnectAttempts() {
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void stopAutoReconnect() {
    _resetReconnectAttempts();
    _stopConnectionMonitoring();
  }

  Future<void> setAutoReconnect(bool enabled) async {
    _autoConnectEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoConnectEnabled', enabled);
    if (!enabled) stopAutoReconnect();
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _connectionMonitorTimer?.cancel();
    _connectivitySubscription?.cancel();
  }
}