import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:claude_iot/services/services.commun.dart' hide CommunicationMode;
import 'package:claude_iot/services/services.bluetooth.dart';
import 'package:claude_iot/utils/persistence_connexion.dart';
import 'package:claude_iot/server/server_front.dart';
import 'package:claude_iot/server/server_back.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// (Enums and TerminalLine class remain the same)
enum ConnectionMode { none, bluetooth, wifi }

enum ConnectionStatus { deconnected, connecting, connected }

enum TerminalTextType { input, system, info, success, error }

class TerminalLine {
  final String text;
  final TerminalTextType type;

  TerminalLine({required this.text, required this.type});
}

// Nouvelle classe pour gérer l'historique des appareils
class DeviceHistory {
  final String id;
  final String name;
  final String address;
  final ConnectionMode mode;
  final DateTime lastConnected;
  final dynamic protocol; // BluetoothProtocol ou WiFiProtocol

  DeviceHistory({
    required this.id,
    required this.name,
    required this.address,
    required this.mode,
    required this.lastConnected,
    this.protocol,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'mode': mode.index,
      'lastConnected': lastConnected.millisecondsSinceEpoch,
      'protocol': protocol?.index,
    };
  }

  factory DeviceHistory.fromMap(Map<String, dynamic> map) {
    return DeviceHistory(
      id: map['id'],
      name: map['name'],
      address: map['address'],
      mode: ConnectionMode.values[map['mode']],
      lastConnected: DateTime.fromMillisecondsSinceEpoch(map['lastConnected']),
      protocol: map['protocol'] != null
          ? (map['mode'] == ConnectionMode.bluetooth.index
                ? BluetoothProtocol.values[map['protocol']]
                : WiFiProtocol.values[map['protocol']])
          : null,
    );
  }
}

class DeviceHistoryManager {
  static const String _storageKey = 'device_history';
  static const int _maxDevices = 10;

  Future<List<DeviceHistory>> getDeviceHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? historyList = prefs.getStringList(_storageKey);

    if (historyList == null) return [];

    return historyList.map((jsonString) {
      final map = json.decode(jsonString);
      return DeviceHistory.fromMap(map);
    }).toList();
  }

  Future<void> addDeviceToHistory(DeviceHistory device) async {
    final List<DeviceHistory> history = await getDeviceHistory();

    // Retirer l'appareil s'il existe déjà
    history.removeWhere((d) => d.id == device.id);

    // Ajouter le nouvel appareil en tête
    history.insert(0, device);

    // Garder seulement les 10 premiers
    final List<DeviceHistory> limitedHistory = history
        .take(_maxDevices)
        .toList();

    final prefs = await SharedPreferences.getInstance();
    final List<String> historyJson = limitedHistory.map((device) {
      return json.encode(device.toMap());
    }).toList();

    await prefs.setStringList(_storageKey, historyJson);
  }

  Future<void> clearDeviceHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

void main() {
  runApp(const TerminalApp());
}

class TerminalApp extends StatelessWidget {
  const TerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Terminal IoT',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const TerminalScreen(),
    );
  }
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with WidgetsBindingObserver {
  late PersistenceConnexion _persistenceConnexion;
  final DeviceHistoryManager _deviceHistoryManager = DeviceHistoryManager();
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<TerminalLine> _outputLines = [];

  // New controllers for Wi-Fi input
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '81',
  ); // Default port for WebSocket

  // Instances des services
  final CommunicationService _communicationService = CommunicationService();

  // Variables d'état du terminal
  ConnectionMode _connectionMode = ConnectionMode.none;
  BluetoothProtocol _bluetoothProtocolMode = BluetoothProtocol.classic;
  WiFiProtocol _wifiProtocolMode =
      WiFiProtocol.http; // Set HTTP as default for Wi-Fi
  ConnectionStatus _connectionStatus = ConnectionStatus.deconnected;
  String _connectedDevice = '';
  String? _connectedDeviceName;

  // New state variables for Bluetooth
  List<BluetoothDevice> _discoveredBluetoothDevices = [];
  BluetoothDevice? _selectedBluetoothDevice;
  bool _isScanningBluetooth = false;

  // Variables pour le mode serveur
  bool _isServerMode = false;
  bool _serverConnected = false;
  String _serverStatusMessage = 'Non connecté au serveur';
  Timer? _serverMessagesTimer;
  List<dynamic> _serverMessages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeTerminal();
    _communicationService.initialize();
    _initializePersistenceConnexion();
    _listenToConnectionChanges();
    _listenToReceivedData();
    _checkInitialConnectivity();
    _loadServerSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistenceConnexion.dispose();
    _commandController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _scrollController.dispose();
    _communicationService.dispose();
    _stopServerMessagesPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRestoreConnection();
    }
  }

  Future<void> _checkAndRestoreConnection() async {
    if (_connectionStatus == ConnectionStatus.deconnected &&
        _persistenceConnexion.autoConnectEnabled) {
      _addOutputLine(
        "🔄 Vérification de la connexion au retour...",
        TerminalTextType.info,
      );
      await _persistenceConnexion.attemptAutoReconnect();
    }
  }

  void _initializeTerminal() {
    _addOutputLine("Terminal IoT prêt", TerminalTextType.system);
    _addOutputLine(
      "Tapez 'aide' pour la liste des commandes",
      TerminalTextType.info,
    );
  }

  void _listenToConnectionChanges() {
    _communicationService.globalConnectionStateStream.listen((isConnected) {
      if (!isConnected && _connectionStatus == ConnectionStatus.connected) {
        // Déconnexion involontaire détectée
        _addOutputLine("⚡ Déconnexion détectée", TerminalTextType.error);
        if (_persistenceConnexion.autoConnectEnabled &&
            !_persistenceConnexion.isReconnecting) {
          _persistenceConnexion.startAutoReconnect();
        }
      }

      setState(() {
        _connectionStatus = isConnected
            ? ConnectionStatus.connected
            : ConnectionStatus.deconnected;
        if (!isConnected) {
          _connectedDevice = '';
        }
      });
    });

    _communicationService.bluetoothEnabledStream.listen((isEnabled) {
      _addOutputLine(
        "Bluetooth est ${isEnabled ? 'activé' : 'désactivé'}.",
        TerminalTextType.info,
      );
    });
  }

  void _listenToReceivedData() {
    _communicationService.globalReceivedDataStream.listen((data) {
      _addOutputLine("<<< RCV: $data", TerminalTextType.info);
    });
  }

  void _initializePersistenceConnexion() {
    _persistenceConnexion = PersistenceConnexion(
      onLogMessage: (message) {
        _addOutputLine(message, TerminalTextType.system);
      },
      onConnectionStatusChanged: (connected) {
        setState(() {
          _connectionStatus = connected
              ? ConnectionStatus.connected
              : ConnectionStatus.deconnected;
        });
      },
      onReconnectStarted: () {
        _addOutputLine(
          "🔄 Reconnexion automatique en cours...",
          TerminalTextType.info,
        );
      },
      onReconnectSuccess: (ip, port, microcontrollerType) {
        _addOutputLine(
          "✅ Reconnexion Wi-Fi réussie à $ip:$port",
          TerminalTextType.success,
        );
        setState(() {
          _connectionStatus = ConnectionStatus.connected;
          _connectedDevice = "$ip:$port";
        });
      },
      onBluetoothReconnectSuccess: (device) {
        _addOutputLine(
          "✅ Reconnexion Bluetooth réussie à ${device.name}",
          TerminalTextType.success,
        );
        setState(() {
          _connectionStatus = ConnectionStatus.connected;
          _connectedDeviceName = device.name;
          _connectedDevice = "${device.name} (${device.id})";
        });
      },
      onReconnectFailed: (error) {
        _addOutputLine("❌ Échec reconnexion: $error", TerminalTextType.error);
      },
      communicationService: _communicationService,
    );

    _persistenceConnexion.initialize().then((_) {
      // Tentative de reconnexion automatique après initialisation
      _attemptAutoReconnectOnStartup();
    });
  }

  Future<void> _attemptAutoReconnectOnStartup() async {
    await Future.delayed(Duration(seconds: 2));

    final success = await _persistenceConnexion.attemptAutoReconnect();
    if (success) {
      _addOutputLine(
        "✅ Reconnexion automatique au démarrage réussie",
        TerminalTextType.success,
      );

      setState(() {
        _connectionStatus = ConnectionStatus.connected;

        // Mettre à jour l'interface selon le mode avec les valeurs persistantes
        if (_persistenceConnexion.lastConnectionMode == 'wifi') {
          _connectionMode = ConnectionMode.wifi;
          _wifiProtocolMode =
              _persistenceConnexion.lastWifiProtocol ?? WiFiProtocol.http;

          // Mettre à jour les contrôleurs avec les valeurs persistées
          if (_persistenceConnexion.lastConnectedIP != null) {
            _ipController.text = _persistenceConnexion.lastConnectedIP!;
          }
          if (_persistenceConnexion.lastConnectedPort != null) {
            _portController.text = _persistenceConnexion.lastConnectedPort!
                .toString();
          }

          _connectedDevice =
              "${_persistenceConnexion.lastConnectedIP}:${_persistenceConnexion.lastConnectedPort}";
          _connectedDeviceName = "Appareil Wi-Fi";
        } else if (_persistenceConnexion.lastConnectionMode == 'bluetooth') {
          _connectionMode = ConnectionMode.bluetooth;
          _bluetoothProtocolMode =
              _persistenceConnexion.lastBluetoothProtocol ??
              BluetoothProtocol.classic;
          _connectedDeviceName =
              _persistenceConnexion.lastBluetoothDeviceName ??
              'Appareil Bluetooth';
          _connectedDevice =
              "${_connectedDeviceName} (${_persistenceConnexion.lastBluetoothDeviceId})";
        }
      });
    }
  }

  Future<void> _checkInitialConnectivity() async {
    final bool isBluetoothEnabled = await _communicationService
        .isBluetoothEnabled();
    _addOutputLine(
      "Vérification initiale: Bluetooth ${isBluetoothEnabled ? 'activé' : 'désactivé'}",
      TerminalTextType.info,
    );

    final bool isWifiConnected = await _communicationService.isWifiConnected();
    _addOutputLine(
      "Vérification initiale: Wi-Fi ${isWifiConnected ? 'connecté' : 'déconnecté'}",
      TerminalTextType.info,
    );
  }

  void _addOutputLine(String text, TerminalTextType type) {
    setState(() {
      _outputLines.add(TerminalLine(text: text, type: type));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    });
  }

  void _executeCommand(String command) {
    if (command.isEmpty) return;

    final parts = command.toLowerCase().split(' ');
    final cmd = parts[0];

    switch (cmd) {
      case 'aide':
        _showHelp();
        break;
      case 'effacer':
        _clearTerminal();
        break;
      case 'deconnexion':
        // MODIFICATION: Déconnecter soit le serveur soit l'appareil
        if (_serverConnected) {
          _disconnectServer();
        } else {
          _disconnectDevice();
        }
        break;
      case 'statut':
        _showStatus();
        break;
      case 'bluetooth':
        _setConnectionMode(ConnectionMode.bluetooth);
        break;
      case 'wifi':
        _setConnectionMode(ConnectionMode.wifi);
        break;
      case 'persistance':
        _showPersistenceStatus();
        break;
      case 'test-serveur':
        _testServerConnection();
        break;
      case 'test-http':
        if (_connectionMode == ConnectionMode.wifi &&
            _connectionStatus == ConnectionStatus.connected) {
          _testHttpConnection();
        } else {
          _addOutputLine("Non connecté en Wi-Fi", TerminalTextType.error);
        }
        break;
      case 'reconnexion-auto':
        final parts = command.split(' ');
        if (parts.length > 1) {
          final enabled = parts[1] == 'on';
          _persistenceConnexion.setAutoReconnect(enabled);
          _addOutputLine(
            "Reconnexion auto ${enabled ? 'activée' : 'désactivée'}",
            enabled ? TerminalTextType.success : TerminalTextType.info,
          );
        } else {
          _addOutputLine(
            "Usage: reconnexion-auto on/off",
            TerminalTextType.error,
          );
        }
        break;
      case 'effacer-historique':
        _persistenceConnexion.clearConnectionHistory();
        _deviceHistoryManager.clearDeviceHistory();
        _addOutputLine(
          "Historique de connexion effacé",
          TerminalTextType.success,
        );
        break;
      default:
        // CORRECTION: Permettre l'envoi si serveur connecté OU appareil connecté
        if (_connectionStatus != ConnectionStatus.connected &&
            !_serverConnected) {
          _addOutputLine(
            "Aucun appareil n'est connecté. Impossible d'envoyer la commande '$command'.",
            TerminalTextType.error,
          );
        } else {
          _addOutputLine("Commande envoyée: '$command'", TerminalTextType.info);
          _sendCommandToDevice(command);
        }
        break;
    }
    _commandController.clear();
  }

  void _showPersistenceStatus() {
    final status = _persistenceConnexion.getConnectionStatus();
    _addOutputLine("=== STATUT PERSISTANCE ===", TerminalTextType.system);
    _addOutputLine(
      "Mode: ${status['lastConnectionMode'] ?? 'Aucun'}",
      TerminalTextType.info,
    );
    _addOutputLine(
      "Reconnexion auto: ${status['autoConnectEnabled'] ? 'ON' : 'OFF'}",
      status['autoConnectEnabled']
          ? TerminalTextType.success
          : TerminalTextType.error,
    );
    _addOutputLine(
      "En reconnexion: ${status['isReconnecting'] ? 'OUI' : 'NON'}",
      TerminalTextType.info,
    );

    if (status['wifiSettings']['ip'] != null) {
      _addOutputLine(
        "Wi-Fi: ${status['wifiSettings']['ip']}:${status['wifiSettings']['port']}",
        TerminalTextType.info,
      );
    }

    if (status['bluetoothSettings']['deviceName'] != null) {
      _addOutputLine(
        "Bluetooth: ${status['bluetoothSettings']['deviceName']}",
        TerminalTextType.info,
      );
    }
  }

  void _showHelp() {
    _addOutputLine("Commandes disponibles:", TerminalTextType.system);
    _addOutputLine(
      "  - aide: Affiche ce message d'aide",
      TerminalTextType.system,
    );
    _addOutputLine(
      "  - effacer: Nettoie l'historique du terminal",
      TerminalTextType.system,
    );
    _addOutputLine(
      "  - deconnexion: Déconnecte l'appareil actuel",
      TerminalTextType.system,
    );
    _addOutputLine(
      "  - statut: Affiche le statut de connexion",
      TerminalTextType.system,
    );
    _addOutputLine(
      "  - bluetooth: Passe en mode Bluetooth et affiche les options de scan/connexion",
      TerminalTextType.system,
    );
    _addOutputLine(
      "  - wifi: Passe en mode Wi-Fi et affiche les options de connexion IP/Port",
      TerminalTextType.system,
    );
    _addOutputLine(
      "  - [votre_commande]: Envoie une commande à l'appareil connecté",
      TerminalTextType.system,
    );
  }

  void _clearTerminal() {
    setState(() {
      _outputLines.clear();
    });
    _initializeTerminal();
  }

  Future<void> _testHttpConnection() async {
    final String ip = _persistenceConnexion.lastConnectedIP ?? '';
    final int? port = _persistenceConnexion.lastConnectedPort;

    if (ip.isEmpty || port == null) {
      _addOutputLine("❌ IP/Port non définis", TerminalTextType.error);
      return;
    }

    _addOutputLine(
      "🧪 Test de connexion HTTP à $ip:$port",
      TerminalTextType.info,
    );

    try {
      final result = await _communicationService.sendHttpCommand(
        ip: ip,
        port: port,
        command: 'test',
      );

      _addOutputLine(
        "Code réponse: ${result.message}",
        result.success ? TerminalTextType.success : TerminalTextType.error,
      );

      if (result.message.contains('404')) {
        _addOutputLine(
          "ℹ️ Le serveur répond mais le endpoint '/test' n'existe pas",
          TerminalTextType.info,
        );
        _addOutputLine(
          "ℹ️ Essayez une commande spécifique à votre appareil",
          TerminalTextType.info,
        );
      }
    } catch (e) {
      _addOutputLine(
        "❌ Erreur de test: ${e.toString()}",
        TerminalTextType.error,
      );
    }
  }

  Future<void> _connectToSelectedBluetoothDevice() async {
    if (_selectedBluetoothDevice == null) {
      Fluttertoast.showToast(msg: "Sélectionnez un appareil");
      return;
    }

    try {
      setState(() {
        _connectionStatus = ConnectionStatus.connecting;
      });

      final success = await _persistenceConnexion.connectBluetooth(
        _selectedBluetoothDevice!,
        _bluetoothProtocolMode,
      );

      if (success) {
        // Ajouter à l'historique
        final deviceHistory = DeviceHistory(
          id: _selectedBluetoothDevice!.id,
          name: _selectedBluetoothDevice!.name,
          address: _selectedBluetoothDevice!.id,
          mode: ConnectionMode.bluetooth,
          lastConnected: DateTime.now(),
          protocol: _bluetoothProtocolMode,
        );
        await _deviceHistoryManager.addDeviceToHistory(deviceHistory);

        setState(() {
          _connectionStatus = ConnectionStatus.connected;
          _connectionMode = ConnectionMode.bluetooth;
          _connectedDeviceName = _selectedBluetoothDevice!.name;
          _connectedDevice =
              "${_selectedBluetoothDevice!.name} (${_selectedBluetoothDevice!.id})";
        });
        Fluttertoast.showToast(
          msg: "Connecté à ${_selectedBluetoothDevice!.name} !",
        );
      } else {
        setState(() {
          _connectionStatus = ConnectionStatus.deconnected;
        });
        Fluttertoast.showToast(msg: "Échec de connexion Bluetooth");
      }
    } catch (e) {
      setState(() {
        _connectionStatus = ConnectionStatus.deconnected;
      });
      Fluttertoast.showToast(msg: "Erreur connexion: ${e.toString()}");
    }
  }

  // --- Wi-Fi specific methods ---
  Future<void> _connectToWifiDevice() async {
    final String ip = _ipController.text.trim();
    final int? port = int.tryParse(_portController.text.trim());

    if (ip.isEmpty || port == null) {
      Fluttertoast.showToast(msg: "IP/Port invalide");
      return;
    }

    setState(() {
      _connectionStatus = ConnectionStatus.connecting;
    });

    final success = await _persistenceConnexion.connectWifi(
      ip,
      port,
      _wifiProtocolMode,
    );

    if (success) {
      // Ajouter à l'historique
      final deviceHistory = DeviceHistory(
        id: '$ip:$port',
        name: 'Appareil Wi-Fi',
        address: '$ip:$port',
        mode: ConnectionMode.wifi,
        lastConnected: DateTime.now(),
        protocol: _wifiProtocolMode,
      );
      await _deviceHistoryManager.addDeviceToHistory(deviceHistory);

      setState(() {
        _connectionStatus = ConnectionStatus.connected;
        _connectionMode = ConnectionMode.wifi;
        _connectedDevice = "$ip:$port";
      });
      Fluttertoast.showToast(msg: "Connecté avec succès!");
    } else {
      setState(() {
        _connectionStatus = ConnectionStatus.deconnected;
      });
      Fluttertoast.showToast(msg: "Échec de connexion");
    }
  }

  // AJOUT: Méthode pour récupérer les messages du serveur
  Future<void> _fetchServerMessages() async {
    if (!_isServerMode || !_serverConnected) return;

    final result = await ServerBack.getMessages();

    setState(() {
      if (result['success'] == true) {
        final List<dynamic> newMessages = result['messages'] ?? [];

        // Ajouter seulement les nouveaux messages au terminal
        for (var message in newMessages) {
          final String formattedMessage = _formatServerMessage(message);
          if (!_serverMessages.any(
            (msg) => _formatServerMessage(msg) == formattedMessage,
          )) {
            _addOutputLine(
              "<< Serveur: $formattedMessage",
              TerminalTextType.info,
            );
          }
        }

        _serverMessages = newMessages;
      } else {
        _addOutputLine(
          ">> Erreur récupération messages: ${result['message']}",
          TerminalTextType.error,
        );
      }
    });
  }

  // AJOUT: Formater les messages serveur
  String _formatServerMessage(dynamic message) {
    try {
      if (message is Map) {
        final deviceId = message['device_id']?.toString() ?? 'Inconnu';
        final messageText = message['message']?.toString() ?? 'Pas de message';
        final createdAt = message['created_at']?.toString() ?? '';

        String formattedDate = _formatDate(createdAt);
        return '$messageText${formattedDate.isNotEmpty ? ' -- $formattedDate' : ''}';
      } else if (message is String) {
        return message;
      } else {
        return message.toString();
      }
    } catch (e) {
      return 'Erreur formatage: ${message.toString()}';
    }
  }

  // AJOUT: Formater la date
  String _formatDate(String isoDate) {
    try {
      if (isoDate.isEmpty) return '';

      final date = DateTime.parse(isoDate);
      final localDate = date.toLocal();

      final day = localDate.day.toString().padLeft(2, '0');
      final month = localDate.month.toString().padLeft(2, '0');
      final year = localDate.year.toString();
      final hour = localDate.hour.toString().padLeft(2, '0');
      final minute = localDate.minute.toString().padLeft(2, '0');
      final second = localDate.second.toString().padLeft(2, '0');

      return '$day/$month/$year $hour:$minute:$second';
    } catch (e) {
      return '';
    }
  }

  // AJOUT: Démarrer le polling des messages serveur
  void _startServerMessagesPolling() {
    _serverMessagesTimer?.cancel();
    _serverMessagesTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      if (_isServerMode && _serverConnected) {
        _fetchServerMessages();
      }
    });
  }

  // AJOUT: Arrêter le polling
  void _stopServerMessagesPolling() {
    _serverMessagesTimer?.cancel();
    _serverMessagesTimer = null;
  }

  Future<void> _disconnectDevice() async {
    if (_connectionStatus == ConnectionStatus.deconnected) {
      _addOutputLine(
        "Aucun appareil n'est actuellement connecté.",
        TerminalTextType.info,
      );
      return;
    }
    _addOutputLine("Déconnexion de l'appareil...", TerminalTextType.info);
    try {
      _communicationService.disconnectAll();
      _addOutputLine("Déconnecté avec succès.", TerminalTextType.success);
      // Après déconnexion, réafficher la section de connexion
      _persistenceConnexion.stopAutoReconnect();
      setState(() {});
    } catch (e) {
      _addOutputLine(
        "Erreur lors de la déconnexion: ${e.toString()}",
        TerminalTextType.error,
      );
    }
  }

  Future<void> _sendCommandToDevice(String command) async {
    try {
      // Mode serveur
      if (_isServerMode && _serverConnected) {
        _addOutputLine(
          "🌐 Envoi au serveur: '$command'",
          TerminalTextType.info,
        );

        final result = await ServerBack.sendCommand(command);

        if (result['success'] == true) {
          _addOutputLine(
            "✅ Réponse serveur: ${result['message']}",
            TerminalTextType.success,
          );
        } else {
          _addOutputLine(
            "❌ Erreur serveur: ${result['message']}",
            TerminalTextType.error,
          );
        }
        return;
      }

      // Mode Bluetooth
      if (_connectionMode == ConnectionMode.bluetooth) {
        await _communicationService.sendBluetoothCommand(command);
        _addOutputLine(
          "📡 Commande Bluetooth envoyée: '$command'",
          TerminalTextType.success,
        );
      }
      // Mode Wi-Fi direct
      else if (_connectionMode == ConnectionMode.wifi) {
        final String ip = _persistenceConnexion.lastConnectedIP ?? '';
        final int? port = _persistenceConnexion.lastConnectedPort;

        if (ip.isEmpty || port == null) {
          _addOutputLine("❌ IP/Port non définis", TerminalTextType.error);
          return;
        }

        if (_wifiProtocolMode == WiFiProtocol.http) {
          _addOutputLine(
            "🌐 Envoi HTTP à $ip:$port : '$command'",
            TerminalTextType.info,
          );

          try {
            final result = await _communicationService.sendHttpCommand(
              ip: ip,
              port: port,
              command: command,
            );

            if (result.success) {
              _addOutputLine(
                "✅ Réponse HTTP: ${result.message}",
                TerminalTextType.success,
              );
            } else {
              _addOutputLine(
                "❌ Erreur HTTP: ${result.message}",
                TerminalTextType.error,
              );
            }
          } catch (e) {
            _addOutputLine(
              "❌ Erreur HTTP: ${e.toString()}",
              TerminalTextType.error,
            );
          }
        } else if (_wifiProtocolMode == WiFiProtocol.websocket) {
          _communicationService.sendWebSocketMessage(command);
          _addOutputLine(
            "🔌 Message WebSocket envoyé: '$command'",
            TerminalTextType.success,
          );
        }
      }
    } catch (e) {
      _addOutputLine("❌ Erreur envoi: ${e.toString()}", TerminalTextType.error);
    }
  }

  void _showStatus() {
    _addOutputLine("=== STATUT SYSTÈME ===", TerminalTextType.system);
    _addOutputLine(
      "Mode connexion: ${_connectionMode.name}",
      TerminalTextType.info,
    );

    _addOutputLine(
      "Mode serveur: ${_isServerMode ? 'ACTIVÉ' : 'DÉSACTIVÉ'}",
      _isServerMode ? TerminalTextType.info : TerminalTextType.system,
    );

    if (_isServerMode) {
      _addOutputLine(
        "Mode serveur: ${_serverConnected ? 'CONNECTÉ' : 'DÉCONNECTÉ'}",
        _serverConnected ? TerminalTextType.success : TerminalTextType.error,
      );
      if (_serverConnected) {
        _addOutputLine(
          "URL serveur: ${ServerBack.activeBaseUrl}",
          TerminalTextType.info,
        );
      }
    }

    if (_connectionMode == ConnectionMode.bluetooth) {
      _addOutputLine(
        "Protocole Bluetooth: ${_bluetoothProtocolMode.name}",
        TerminalTextType.info,
      );
    } else if (_connectionMode == ConnectionMode.wifi) {
      _addOutputLine(
        "Protocole Wi-Fi: ${_wifiProtocolMode.name}",
        TerminalTextType.info,
      );
    }

    _addOutputLine(
      "Statut connexion: ${_connectionStatus.name}",
      _connectionStatus == ConnectionStatus.connected
          ? TerminalTextType.success
          : TerminalTextType.error,
    );

    if (_connectionStatus == ConnectionStatus.connected) {
      _addOutputLine("Appareil: $_connectedDevice", TerminalTextType.info);

      // AJOUT: Afficher les détails de connexion actuels
      if (_connectionMode == ConnectionMode.wifi) {
        final ip = _persistenceConnexion.lastConnectedIP ?? 'Non défini';
        final port = _persistenceConnexion.lastConnectedPort ?? 0;
        _addOutputLine("IP: $ip, Port: $port", TerminalTextType.info);
      }
    }
  }

  void _setConnectionMode(ConnectionMode mode) {
    setState(() {
      _connectionMode = mode;
      _addOutputLine(
        "Mode de connexion changé: ${mode.name}",
        TerminalTextType.success,
      );
      // Clear previous mode related state
      _discoveredBluetoothDevices.clear();
      _selectedBluetoothDevice = null;
      _isScanningBluetooth = false;
      _ipController.clear();
      _portController.text = _wifiProtocolMode == WiFiProtocol.http
          ? '80'
          : '81'; // Reset to default port based on protocol
      // Afficher la section de connexion quand on change de mode
    });
  }

  // Nouvelle méthode pour afficher l'historique des appareils
  void _showDeviceHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Appareils récents', style: GoogleFonts.roboto()),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  tabs: [
                    Tab(text: 'Wi-Fi'),
                    Tab(text: 'Bluetooth'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildWifiHistoryList(),
                      _buildBluetoothHistoryList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
          TextButton(
            onPressed: () {
              _clearDeviceHistory();
              Navigator.pop(context);
              Fluttertoast.showToast(msg: "Historique effacé");
            },
            child: const Text('Effacer l\'historique'),
          ),
        ],
      ),
    );
  }

  Widget _buildProtocolsTab(BuildContext context, StateSetter setStateDialog) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configuration des Protocoles',
            style: GoogleFonts.roboto(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 20),

          Text(
            'Protocole Bluetooth par défaut:',
            style: GoogleFonts.roboto(fontSize: 14),
          ),
          SizedBox(height: 8),

          // Bluetooth Classic
          ListTile(
            leading: Icon(Icons.bluetooth, color: Colors.blue),
            title: Text('Bluetooth Classic', style: GoogleFonts.roboto()),
            trailing: Radio<BluetoothProtocol>(
              value: BluetoothProtocol.classic,
              groupValue: _bluetoothProtocolMode,
              onChanged: (value) {
                setStateDialog(() {
                  setState(() {
                    _bluetoothProtocolMode = value!;
                  });
                });
              },
            ),
            onTap: () {
              setStateDialog(() {
                setState(() {
                  _bluetoothProtocolMode = BluetoothProtocol.classic;
                });
              });
            },
          ),

          // Bluetooth BLE
          ListTile(
            leading: Icon(Icons.bluetooth_connected, color: Colors.blue),
            title: Text(
              'Bluetooth Low Energy (BLE)',
              style: GoogleFonts.roboto(),
            ),
            trailing: Radio<BluetoothProtocol>(
              value: BluetoothProtocol.ble,
              groupValue: _bluetoothProtocolMode,
              onChanged: (value) {
                setStateDialog(() {
                  setState(() {
                    _bluetoothProtocolMode = value!;
                  });
                });
              },
            ),
            onTap: () {
              setStateDialog(() {
                setState(() {
                  _bluetoothProtocolMode = BluetoothProtocol.ble;
                });
              });
            },
          ),

          SizedBox(height: 20),
          Text(
            'Protocole Wi-Fi par défaut:',
            style: GoogleFonts.roboto(fontSize: 14),
          ),
          SizedBox(height: 8),

          // HTTP
          ListTile(
            leading: Icon(Icons.http, color: Colors.blue),
            title: Text('HTTP', style: GoogleFonts.roboto()),
            trailing: Radio<WiFiProtocol>(
              value: WiFiProtocol.http,
              groupValue: _wifiProtocolMode,
              onChanged: (value) {
                setStateDialog(() {
                  setState(() {
                    _wifiProtocolMode = value!;
                    _portController.text = '80';
                  });
                });
              },
            ),
            onTap: () {
              setStateDialog(() {
                setState(() {
                  _wifiProtocolMode = WiFiProtocol.http;
                  _portController.text = '80';
                });
              });
            },
          ),

          // WebSocket
          ListTile(
            leading: Icon(Icons.online_prediction, color: Colors.blue),
            title: Text('WebSocket', style: GoogleFonts.roboto()),
            trailing: Radio<WiFiProtocol>(
              value: WiFiProtocol.websocket,
              groupValue: _wifiProtocolMode,
              onChanged: (value) {
                setStateDialog(() {
                  setState(() {
                    _wifiProtocolMode = value!;
                    _portController.text = '81';
                  });
                });
              },
            ),
            onTap: () {
              setStateDialog(() {
                setState(() {
                  _wifiProtocolMode = WiFiProtocol.websocket;
                  _portController.text = '81';
                });
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildServerTab(BuildContext context, StateSetter setStateDialog) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configuration du Serveur',
            style: GoogleFonts.roboto(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 20),

          // Switch mode serveur
          Card(
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.cloud,
                        color: _isServerMode ? Colors.blue : Colors.grey,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mode Serveur',
                              style: GoogleFonts.roboto(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'Utiliser un serveur cloud pour les commandes',
                              style: GoogleFonts.roboto(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isServerMode,
                        onChanged: (value) =>
                            _toggleServerMode(value, setStateDialog),
                        activeColor: Colors.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 20),

          // Statut du serveur
          if (_isServerMode) ...[
            Card(
              elevation: 2,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Statut du Serveur',
                      style: GoogleFonts.roboto(fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _serverConnected
                            ? Colors.green[50]
                            : Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _serverConnected
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _serverConnected
                                ? Icons.cloud_done
                                : Icons.cloud_off,
                            color: _serverConnected
                                ? Colors.green
                                : Colors.orange,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _serverStatusMessage,
                                  style: GoogleFonts.roboto(
                                    color: _serverConnected
                                        ? Colors.green
                                        : Colors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (_serverConnected &&
                                    ServerBack.activeBaseUrl.isNotEmpty)
                                  Text(
                                    'URL: ${ServerBack.activeBaseUrl}',
                                    style: GoogleFonts.roboto(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.cloud, size: 20),
                            label: Text('Tester la Connexion'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _testServerConnection,
                          ),
                        ),
                        SizedBox(width: 12),
                        IconButton(
                          icon: Icon(Icons.settings, color: Colors.blue),
                          onPressed: _showServerConfigModal,
                          tooltip: 'Configurer le serveur',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // Informations mode serveur
            Card(
              elevation: 1,
              color: Colors.blue[50],
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'En mode serveur, les commandes sont envoyées via le cloud. '
                        'Assurez-vous que votre appareil est configuré pour communiquer avec le serveur.',
                        style: GoogleFonts.roboto(
                          fontSize: 12,
                          color: Colors.blue[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Message quand le mode serveur est désactivé
            Card(
              elevation: 1,
              color: Colors.grey[100],
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'Mode Serveur Désactivé',
                      style: GoogleFonts.roboto(fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Activez le mode serveur pour utiliser les fonctionnalités cloud '
                      'et centraliser vos commandes IoT.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.roboto(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWifiHistoryList() {
    return FutureBuilder<List<DeviceHistory>>(
      future: _deviceHistoryManager.getDeviceHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text('Aucun appareil Wi-Fi récent'));
        }

        final wifiDevices = snapshot.data!
            .where((device) => device.mode == ConnectionMode.wifi)
            .toList();

        if (wifiDevices.isEmpty) {
          return Center(child: Text('Aucun appareil Wi-Fi récent'));
        }

        return ListView.builder(
          itemCount: wifiDevices.length,
          itemBuilder: (context, index) {
            final device = wifiDevices[index];
            return ListTile(
              leading: Icon(Icons.wifi, color: Colors.blue),
              title: Text(device.name),
              subtitle: Text(device.address),
              trailing: Text(_formatDeviceHistoryDate(device.lastConnected)),
              onTap: () {
                // Extraire IP et port de l'adresse
                final parts = device.address.split(':');
                if (parts.length == 2) {
                  _ipController.text = parts[0];
                  _portController.text = parts[1];
                  _wifiProtocolMode =
                      device.protocol as WiFiProtocol? ?? WiFiProtocol.http;
                  _connectToWifiDevice();
                }
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBluetoothHistoryList() {
    return FutureBuilder<List<DeviceHistory>>(
      future: _deviceHistoryManager.getDeviceHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text('Aucun appareil Bluetooth récent'));
        }

        final bluetoothDevices = snapshot.data!
            .where((device) => device.mode == ConnectionMode.bluetooth)
            .toList();

        if (bluetoothDevices.isEmpty) {
          return Center(child: Text('Aucun appareil Bluetooth récent'));
        }

        return ListView.builder(
          itemCount: bluetoothDevices.length,
          itemBuilder: (context, index) {
            final device = bluetoothDevices[index];
            return ListTile(
              leading: Icon(Icons.bluetooth, color: Colors.blue),
              title: Text(
                device.name.isEmpty ? 'Appareil inconnu' : device.name,
              ),
              subtitle: Text(device.address),
              trailing: Text(_formatDeviceHistoryDate(device.lastConnected)),
              onTap: () {
                // Recréer l'objet BluetoothDevice pour la reconnexion
                final bluetoothDevice = BluetoothDevice(
                  id: device.id,
                  name: device.name,
                  isBle: device.protocol == BluetoothProtocol.ble,
                );
                _selectedBluetoothDevice = bluetoothDevice;
                _bluetoothProtocolMode =
                    device.protocol as BluetoothProtocol? ??
                    BluetoothProtocol.classic;
                _connectToSelectedBluetoothDevice();
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  String _formatDeviceHistoryDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _clearDeviceHistory() async {
    await _deviceHistoryManager.clearDeviceHistory();
    Fluttertoast.showToast(msg: "Historique des appareils effacé");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 54, 54, 54),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4784AB),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Terminal IoT',
          style: GoogleFonts.roboto(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            onPressed: _showDeviceHistoryDialog,
          ),
          IconButton(
            icon: Icon(
              Icons.bluetooth,
              color: _connectionMode == ConnectionMode.bluetooth
                  ? Colors.white
                  : Colors.white.withAlpha((0.5 * 255).toInt()),
            ),
            onPressed: () => _showBluetoothConnectionDialog(context),
          ),
          IconButton(
            icon: Icon(
              Icons.wifi,
              color: _connectionMode == ConnectionMode.wifi
                  ? Colors.white
                  : Colors.white.withAlpha((0.5 * 255).toInt()),
            ),
            onPressed: () => _showWifiConnectionDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _showConnectionSettings,
          ),
          // AJOUT: Bouton de déconnexion dans l'AppBar
        ],
      ),
      body: Column(
        children: [
          // Affichage "Connecté à..." en haut, s'il y a une connexion
          if (_connectionStatus == ConnectionStatus.connected ||
              _serverConnected)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: const Color.fromARGB(157, 158, 158, 157),
              child: Row(
                mainAxisAlignment: MainAxisAlignment
                    .spaceBetween, // MODIFICATION: spaceBetween
                children: [
                  Expanded(
                    child: Text(
                      _serverConnected
                          ? 'Connecté au serveur: ${ServerBack.activeBaseUrl}'
                          : 'Connecté à: $_connectedDevice',
                      style: GoogleFonts.roboto(
                        color: const Color.fromARGB(255, 24, 238, 253),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // AJOUT: Bouton de déconnexion dans la barre de connexion
                  IconButton(
                    icon: const Icon(
                      Icons.link_off,
                      color: Colors.red,
                      size: 20,
                    ),
                    onPressed: _disconnectDevice,
                    tooltip: 'Déconnecter',
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white),
                    onPressed: _clearTerminal,
                    tooltip: 'Effacer le terminal',
                  ),
                ],
              ),
            ),

          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _outputLines.length,
              itemBuilder: (context, index) {
                final line = _outputLines[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line.text,
                    style: _getTextStyle(line.type),
                    ),
                );
              },
            ),
          ),
          Container(height: 6, color: const Color.fromARGB(255, 45, 165, 221)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    style: GoogleFonts.robotoMono(
                      color: const Color.fromARGB(255, 250, 249, 249),
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Entrez une commande...',
                      hintStyle: GoogleFonts.robotoMono(
                        color: const Color.fromARGB(255, 206, 205, 207),
                      ),
                      filled: true,
                      fillColor: const Color.fromARGB(255, 85, 85, 85),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(
                          color: Color.fromARGB(255, 248, 245, 245),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(
                          color: Color.fromARGB(255, 24, 3, 207),
                        ),
                      ),
                    ),
                    cursorColor: const Color.fromARGB(206, 43, 10, 230),
                    onSubmitted: _executeCommand,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color.fromARGB(251, 46, 194, 240),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: () => _executeCommand(_commandController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showBluetoothConnectionDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setStateInDialog) {
          return AlertDialog(
            title: Text('Connexion Bluetooth', style: GoogleFonts.roboto()),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<BluetoothProtocol>(
                          title: Text('Classic', style: GoogleFonts.roboto()),
                          value: BluetoothProtocol.classic,
                          groupValue: _bluetoothProtocolMode,
                          onChanged: _isScanningBluetooth
                              ? null
                              : (value) {
                                  setStateInDialog(() {
                                    setState(() {
                                      _bluetoothProtocolMode = value!;
                                    });
                                  });
                                },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<BluetoothProtocol>(
                          title: Text('BLE', style: GoogleFonts.roboto()),
                          value: BluetoothProtocol.ble,
                          groupValue: _bluetoothProtocolMode,
                          onChanged: _isScanningBluetooth
                              ? null
                              : (value) {
                                  setStateInDialog(() {
                                    setState(() {
                                      _bluetoothProtocolMode = value!;
                                    });
                                  });
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isScanningBluetooth
                        ? null
                        : () async {
                            setStateInDialog(() {
                              _isScanningBluetooth = true;
                              _discoveredBluetoothDevices.clear();
                              _selectedBluetoothDevice = null;
                            });
                            await _startBluetoothScanAndPopulateDialog(
                              setStateInDialog,
                            );
                          },
                    child: _isScanningBluetooth
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(width: 10),
                              Text('Recherche en cours...'),
                            ],
                          )
                        : const Text('Scanner les appareils'),
                  ),
                  const SizedBox(height: 20),

                  // Affichage des appareils trouvés avec une hauteur fixe
                  if (_discoveredBluetoothDevices.isNotEmpty)
                    Container(
                      height: 200, // Hauteur fixe au lieu de ConstrainedBox
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ListView.builder(
                        itemCount: _discoveredBluetoothDevices.length,
                        itemBuilder: (context, index) {
                          final device = _discoveredBluetoothDevices[index];
                          return RadioListTile<BluetoothDevice>(
                            title: Text(
                              device.name.isNotEmpty
                                  ? device.name
                                  : 'Appareil inconnu',
                            ),
                            subtitle: Text(device.id),
                            value: device,
                            groupValue: _selectedBluetoothDevice,
                            onChanged: _isScanningBluetooth
                                ? null
                                : (value) {
                                    setState(
                                      () => _selectedBluetoothDevice = value,
                                    );
                                    setStateInDialog(() {});
                                  },
                          );
                        },
                      ),
                    ),

                  // Messages d'état
                  if (_isScanningBluetooth &&
                      _discoveredBluetoothDevices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Text(
                        'Recherche en cours...',
                        style: GoogleFonts.roboto(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  if (!_isScanningBluetooth &&
                      _discoveredBluetoothDevices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Text(
                        'Cliquez sur "Scanner les appareils" pour commencer.',
                        style: GoogleFonts.roboto(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  // Bouton connecter
                  if (_discoveredBluetoothDevices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: ElevatedButton(
                        onPressed: _selectedBluetoothDevice == null
                            ? null
                            : () async {
                                await _connectToSelectedBluetoothDevice();
                                Navigator.pop(context);
                              },
                        child: const Text('Connecter'),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setStateInDialog(() {
                    _isScanningBluetooth = false;
                  });
                  Navigator.pop(context);
                },
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Correction de la méthode de scan
  Future<void> _startBluetoothScanAndPopulateDialog(
    StateSetter setStateInDialog,
  ) async {
    _addOutputLine(
      "Démarrage du scan Bluetooth (protocole: ${_bluetoothProtocolMode.name})...",
      TerminalTextType.info,
    );

    try {
      _communicationService.setActiveMode(CommunicationMode.bluetooth);
      _communicationService.bluetoothManager.setActiveProtocol(
        _bluetoothProtocolMode,
      );

      final bool isBluetoothOn = await _communicationService
          .isBluetoothEnabled();
      if (!isBluetoothOn) {
        _addOutputLine(
          "Bluetooth est désactivé. Tentative d'activation...",
          TerminalTextType.error,
        );
        await _communicationService.setBluetoothEnabled(true);
        await Future.delayed(const Duration(seconds: 3));
        if (!await _communicationService.isBluetoothEnabled()) {
          _addOutputLine(
            "Impossible d'activer le Bluetooth. Abandon.",
            TerminalTextType.error,
          );
          setStateInDialog(() {
            _isScanningBluetooth = false;
          });
          return;
        }
      }

      try {
        final foundDevices = await _communicationService.scanBluetoothDevices(
          protocol: _bluetoothProtocolMode,
          duration: 15,
        );

        // Mise à jour de l'état avec les appareils trouvés
        setStateInDialog(() {
          _discoveredBluetoothDevices = foundDevices;
          _isScanningBluetooth = false;
        });

        if (foundDevices.isNotEmpty) {
          _addOutputLine(
            "${foundDevices.length} appareil(s) Bluetooth trouvé(s).",
            TerminalTextType.success,
          );
          for (final device in foundDevices) {
            final deviceName = device.name.isNotEmpty
                ? device.name
                : 'Appareil inconnu';
            _addOutputLine(
              "  - $deviceName (${device.id})",
              TerminalTextType.info,
            );
          }
        } else {
          _addOutputLine(
            "Aucun appareil Bluetooth trouvé.",
            TerminalTextType.info,
          );
        }
      } catch (scanError) {
        _addOutputLine(
          "Erreur lors du scan Bluetooth: ${scanError.toString()}",
          TerminalTextType.error,
        );
        setStateInDialog(() {
          _isScanningBluetooth = false;
        });
      }
    } catch (e) {
      _addOutputLine(
        "Erreur critique lors du scan Bluetooth: ${e.toString()}",
        TerminalTextType.error,
      );
      setStateInDialog(() {
        _isScanningBluetooth = false;
      });
    }
  }

  void _showWifiConnectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Connexion Wi-Fi', style: GoogleFonts.roboto()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<WiFiProtocol>(
                      title: Text('HTTP', style: GoogleFonts.roboto()),
                      value: WiFiProtocol.http,
                      groupValue: _wifiProtocolMode,
                      onChanged: (value) {
                        setState(() {
                          _wifiProtocolMode = value!;
                          _portController.text = '80';
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<WiFiProtocol>(
                      title: Text('WebSocket', style: GoogleFonts.roboto()),
                      value: WiFiProtocol.websocket,
                      groupValue: _wifiProtocolMode,
                      onChanged: (value) {
                        setState(() {
                          _wifiProtocolMode = value!;
                          _portController.text = '81';
                        });
                      },
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(labelText: 'Adresse IP'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _portController,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _connectToWifiDevice();
                  Navigator.pop(context);
                },
                child: const Text('Connecter'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  // Méthode pour basculer le mode serveur
  // MODIFICATION: Mettre à jour _toggleServerMode
  void _toggleServerMode(bool value, StateSetter setStateDialog) async {
    setStateDialog(() {
      _isServerMode = value;
    });
    setState(() {
      _isServerMode = value;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('server_mode', value);

    if (!value) {
      setState(() {
        _serverConnected = false;
        _serverStatusMessage = 'Mode serveur désactivé';
      });
      _addOutputLine("Mode serveur désactivé", TerminalTextType.info);
      _stopServerMessagesPolling(); // AJOUT: Arrêter le polling
    } else {
      _testServerConnection();
    }
  }

  // MODIFICATION: Mettre à jour _testServerConnection
  Future<void> _testServerConnection() async {
    if (!_isServerMode) return;

    _addOutputLine("🧪 Test de connexion au serveur...", TerminalTextType.info);

    final result = await ServerBack.checkServerStatus();

    setState(() {
      _serverConnected = result['success'] ?? false;
      _serverStatusMessage = result['message'] ?? 'Erreur inconnue';
    });

    if (_serverConnected) {
      _addOutputLine(
        "✅ Serveur connecté: ${ServerBack.activeBaseUrl}",
        TerminalTextType.success,
      );
      _startServerMessagesPolling(); // AJOUT: Démarrer le polling
      _fetchServerMessages(); // AJOUT: Récupérer les messages immédiatement
    } else {
      _addOutputLine(
        "❌ Erreur serveur: ${result['message']}",
        TerminalTextType.error,
      );
      _stopServerMessagesPolling(); // AJOUT: Arrêter le polling
    }
  }

  // MODIFICATION: Mettre à jour _disconnectServer
  void _disconnectServer() {
    setState(() {
      _serverConnected = false;
      _serverStatusMessage = 'Déconnecté';
      _isServerMode = false;
    });

    _stopServerMessagesPolling(); // AJOUT: Arrêter le polling

    _saveServerMode(false);

    _addOutputLine("Déconnecté du serveur", TerminalTextType.info);
  }

  // AJOUT: Sauvegarder le mode serveur
  Future<void> _saveServerMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('server_mode', value);
  }

  // Méthode pour afficher la configuration détaillée du serveur
  void _showServerConfigModal() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          width: MediaQuery.of(context).size.width * 0.75,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(blurRadius: 20, color: Colors.black.withOpacity(0.2)),
            ],
          ),
          child: ServerFront(),
        ),
      ),
    );
  }

  // Charger les paramètres serveur au démarrage
  Future<void> _loadServerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isServerMode = prefs.getBool('server_mode') ?? false;
    });

    if (_isServerMode) {
      // Tester la connexion serveur au démarrage si le mode est activé
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _testServerConnection();
      });
    }
  }

  void _showConnectionSettings() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              constraints: BoxConstraints(maxWidth: 500, maxHeight: 600),
              child: Column(
                children: [
                  // En-tête
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Color(0xFF4784AB),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.settings, color: Colors.white),
                        SizedBox(width: 12),
                        Text(
                          'Paramètres de Connexion',
                          style: GoogleFonts.roboto(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Onglets
                  DefaultTabController(
                    length: 2,
                    child: Expanded(
                      child: Column(
                        children: [
                          TabBar(
                            tabs: [
                              Tab(text: 'Protocoles'),
                              Tab(text: 'Serveur'),
                            ],
                            labelColor: Color(0xFF4784AB),
                            indicatorColor: Color(0xFF4784AB),
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                // Onglet Protocoles (contenu existant)
                                _buildProtocolsTab(context, setStateDialog),
                                // Nouvel onglet Serveur
                                _buildServerTab(context, setStateDialog),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Boutons d'action
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Fermer', style: GoogleFonts.roboto()),
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
    );
  }
}

  TextStyle _getTextStyle(TerminalTextType type) {
  switch (type) {
    case TerminalTextType.input:
      return GoogleFonts.robotoMono(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.normal,
      );
    case TerminalTextType.system:
      return GoogleFonts.robotoMono(
        color: const Color(0xFFCCCCCC),
        fontSize: 14,
        fontWeight: FontWeight.bold, // Gras
      );
    case TerminalTextType.info:
      return GoogleFonts.robotoMono(
        color: const Color(0xFF33CCFF), // Bleu clair
        fontSize: 14,
        fontWeight: FontWeight.bold,
      );
    case TerminalTextType.success:
      return GoogleFonts.robotoMono(
        color: const Color.fromARGB(255, 8, 239, 16), // Vert
        fontSize: 14,
        fontWeight: FontWeight.bold,
      );
    case TerminalTextType.error:
      return GoogleFonts.robotoMono(
        color: const Color(0xFFFF6666), // Rouge
        fontSize: 14,
        fontWeight: FontWeight.bold,
      );
    default:
      return GoogleFonts.robotoMono(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.normal,
      );
  }
}
