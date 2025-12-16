import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:claude_iot/services/services.commun.dart' hide CommunicationMode;
import 'package:claude_iot/services/services.bluetooth.dart';
import 'package:claude_iot/utils/persistence_connexion.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:claude_iot/server/server_back.dart';
import 'package:claude_iot/server/server_front.dart';
import 'dart:convert';
import 'dart:async';

enum ConnectionType { wifi, bluetooth }

// Classe pour l'historique des appareils
class DeviceHistory {
  final String id;
  final String name;
  final String address;
  final ConnectionType type;
  final DateTime lastConnected;
  final dynamic protocol;

  DeviceHistory({
    required this.id,
    required this.name,
    required this.address,
    required this.type,
    required this.lastConnected,
    this.protocol,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'type': type.index,
      'lastConnected': lastConnected.millisecondsSinceEpoch,
      'protocol': protocol?.index,
    };
  }

  factory DeviceHistory.fromMap(Map<String, dynamic> map) {
    return DeviceHistory(
      id: map['id'],
      name: map['name'],
      address: map['address'],
      type: ConnectionType.values[map['type']],
      lastConnected: DateTime.fromMillisecondsSinceEpoch(map['lastConnected']),
      protocol: map['protocol'] != null
          ? (map['type'] == ConnectionType.bluetooth.index
                ? BluetoothProtocol.values[map['protocol']]
                : WiFiProtocol.values[map['protocol']])
          : null,
    );
  }
}

class DeviceHistoryManager {
  static const String _storageKey = 'switch_device_history';
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

    history.removeWhere((d) => d.id == device.id);
    history.insert(0, device);

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

class ESP32ControllerScreen extends StatefulWidget {
  const ESP32ControllerScreen({super.key});

  @override
  State<ESP32ControllerScreen> createState() => _ESP32ControllerScreenState();
}

class _ESP32ControllerScreenState extends State<ESP32ControllerScreen>
    with WidgetsBindingObserver {
  bool _isActuallyConnected = false;
  final List<bool> _switchStates = List.generate(16, (index) => false);
  final List<Map<String, dynamic>> _switchConfigurations = List.generate(
    16,
    (index) => {
      'name': 'Switch ${index + 1}',
      'onCommand': 'ON',
      'offCommand': 'OFF',
      'lastToggleTime': DateTime.now(),
    },
  );

  bool _showConsole = false;
  String _connectionStatus = 'Déconnecté';
  Color _connectionStatusColor = Colors.red;
  ConnectionType _connectionType = ConnectionType.wifi;
  final List<ConsoleMessage> _consoleMessages = [
    ConsoleMessage(
      'Console prête...',
      ConsoleMessageType.system,
      DateTime.now(),
    ),
  ];
  Offset _fabPosition = const Offset(300, 500);

  // Services de communication et persistance
  final CommunicationService _communicationService = CommunicationService();
  late PersistenceConnexion _persistenceConnexion;
  final DeviceHistoryManager _deviceHistoryManager = DeviceHistoryManager();

  // Variables pour Bluetooth
  List<BluetoothDevice> _discoveredBluetoothDevices = [];
  BluetoothDevice? _selectedBluetoothDevice;
  bool _isScanningBluetooth = false;
  BluetoothProtocol _bluetoothProtocol = BluetoothProtocol.classic;

  // Ajoutez ces getters après les variables d'état
  // CORRECTION : Utiliser les valeurs actuelles des contrôleurs
String get _currentIP => _ipController.text.trim().isNotEmpty 
    ? _ipController.text.trim() 
    : _persistenceConnexion.lastConnectedIP ?? '';

int? get _currentPort {
  final portText = _portController.text.trim();
  if (portText.isNotEmpty) {
    return int.tryParse(portText);
  }
  return _persistenceConnexion.lastConnectedPort;
}

  // Nouvelles variables pour le mode serveur
  bool _isServerMode = false;
  bool _serverConnected = false;
  String _serverStatusMessage = 'Non connecté au serveur';
  Timer? _serverMessagesTimer;
  List<dynamic> _serverMessages = [];

  // Mettre à jour le getter de connexion
  bool get _displayConnected {
    if (_isServerMode) {
      return _serverConnected;
    } else {
      return _isActuallyConnected;
    }
  }

  // Variables pour WiFi
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '80',
  );
  WiFiProtocol _wifiProtocol = WiFiProtocol.http;

  // Variable pour le nom de l'appareil connecté
  String? _connectedDeviceName;
  String? _connectedDeviceAddress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
    _loadServerSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistenceConnexion.dispose();
    _ipController.dispose();
    _portController.dispose();
    _communicationService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRestoreConnection();
    }
  }

  Future<void> _checkAndRestoreConnection() async {
    if (_connectionStatus == 'Déconnecté' &&
        _persistenceConnexion.autoConnectEnabled) {
      _addConsoleMessage("🔄 Vérification de la connexion au retour...");
      await _persistenceConnexion.attemptAutoReconnect();
    }
  }

  void _initializeServices() async {
    _communicationService.initialize();
    _initializePersistenceConnexion();
    _listenToConnectionChanges();
    _listenToReceivedData();
    _checkInitialConnectivity();

    // Tentative de reconnexion automatique au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _attemptAutoReconnectOnStartup();
    });
  }

  void _initializePersistenceConnexion() {
    _persistenceConnexion = PersistenceConnexion(
      onLogMessage: (message) {
        _addConsoleMessage(message);
      },
      onConnectionStatusChanged: (connected) {
        setState(() {
          _connectionStatus = connected ? 'Connecté' : 'Déconnecté';
          _connectionStatusColor = connected ? Colors.green : Colors.red;
          _updateConnectionStatus();
        });
      },
      onReconnectStarted: () {
        _addConsoleMessage("🔄 Reconnexion automatique en cours...");
      },
      onReconnectSuccess: (ip, port, microcontrollerType) {
        _addConsoleMessage("✅ Reconnexion Wi-Fi réussie à $ip:$port");
        setState(() {
          _isActuallyConnected = true;
          _connectionStatus = 'Connecté';
          _connectionStatusColor = Colors.green;
          _connectionType = ConnectionType.wifi;
          _connectedDeviceName = 'Appareil Wi-Fi';
          _connectedDeviceAddress = '$ip:$port';
          _updateConnectionStatus();
        });
      },
      onBluetoothReconnectSuccess: (device) {
        _addConsoleMessage("✅ Reconnexion Bluetooth réussie à ${device.name}");
        setState(() {
          _isActuallyConnected = true;
          _connectionStatus = 'Connecté';
          _connectionStatusColor = Colors.green;
          _connectionType = ConnectionType.bluetooth;
          _connectedDeviceName = device.name;
          _connectedDeviceAddress = device.id;
          _selectedBluetoothDevice = device;
          _updateConnectionStatus();
        });
      },
      onReconnectFailed: (error) {
        _addConsoleMessage("❌ Échec reconnexion: $error");
      },
      communicationService: _communicationService,
    );

    _persistenceConnexion.initialize();
  }

  void _addConsoleMessage(String message, {ConsoleMessageType type = ConsoleMessageType.info}) {
  setState(() {
    _consoleMessages.add(ConsoleMessage(message, type, DateTime.now()));
    
    // Limiter le nombre de messages pour éviter les problèmes de performance
    if (_consoleMessages.length > 1000) {
      _consoleMessages.removeRange(0, 100);
    }
  });
}

  // Méthodes spécialisées pour différents types de messages
  void _addSystemMessage(String message) =>
      _addConsoleMessage(message, type: ConsoleMessageType.system);

  Future<void> _attemptAutoReconnectOnStartup() async {
  await Future.delayed(const Duration(seconds: 2));

  final success = await _persistenceConnexion.attemptAutoReconnect();
  if (success) {
    _addConsoleMessage("✅ Reconnexion automatique au démarrage réussie");

    setState(() {
      _isActuallyConnected = true; // ⚠️ AJOUT IMPORTANT
      _connectionStatus = 'Connecté';
      _connectionStatusColor = Colors.green;

      // Mettre à jour l'interface selon le mode avec les valeurs persistantes
      if (_persistenceConnexion.lastConnectionMode == 'wifi') {
        _connectionType = ConnectionType.wifi;
        _wifiProtocol = _persistenceConnexion.lastWifiProtocol ?? WiFiProtocol.http;
        _connectedDeviceName = 'Appareil Wi-Fi';
        _connectedDeviceAddress = '${_persistenceConnexion.lastConnectedIP}:${_persistenceConnexion.lastConnectedPort}';
        
        // Mettre à jour les contrôleurs avec les valeurs persistées
        if (_persistenceConnexion.lastConnectedIP != null) {
          _ipController.text = _persistenceConnexion.lastConnectedIP!;
        }
        if (_persistenceConnexion.lastConnectedPort != null) {
          _portController.text = _persistenceConnexion.lastConnectedPort!.toString();
        }
        
      } else if (_persistenceConnexion.lastConnectionMode == 'bluetooth') {
        _connectionType = ConnectionType.bluetooth;
        _bluetoothProtocol = _persistenceConnexion.lastBluetoothProtocol ?? BluetoothProtocol.classic;
        if (_persistenceConnexion.lastBluetoothDeviceId != null) {
          _selectedBluetoothDevice = BluetoothDevice(
            id: _persistenceConnexion.lastBluetoothDeviceId!,
            name: _persistenceConnexion.lastBluetoothDeviceName ?? 'Appareil Bluetooth',
            isBle: _persistenceConnexion.lastBluetoothProtocol == BluetoothProtocol.ble,
          );
          _connectedDeviceName = _selectedBluetoothDevice!.name;
          _connectedDeviceAddress = _selectedBluetoothDevice!.id;
        }
      }
      _updateConnectionStatus(); // ⚠️ APPELER LA MISE À JOUR
    });
  } else {
    // Si la reconnexion échoue, s'assurer que l'état est cohérent
    setState(() {
      _isActuallyConnected = false;
      _connectionStatus = 'Déconnecté';
      _connectionStatusColor = Colors.red;
      _updateConnectionStatus();
    });
  }
}

  // Charger les paramètres serveur au démarrage
Future<void> _loadServerSettings() async {
  final prefs = await SharedPreferences.getInstance();
  setState(() {
    _isServerMode = prefs.getBool('switch_server_mode') ?? false;
  });
  
  if (_isServerMode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _testServerConnection();
    });
  }
}

// Tester la connexion serveur
Future<void> _testServerConnection() async {
  setState(() {
    _serverStatusMessage = 'Test de connexion au serveur...';
  });

  final result = await ServerBack.checkServerStatus();

  setState(() {
    _serverConnected = result['success'] ?? false;
    _serverStatusMessage = result['message'] ?? 'Erreur inconnue';

    if (_serverConnected) {
      _addConsoleMessage("✅ Connecté au serveur: ${ServerBack.activeBaseUrl}", 
          type: ConsoleMessageType.success);
      _startServerMessagesPolling();
      _fetchServerMessages();
    } else {
      _addConsoleMessage("❌ Erreur serveur: ${result['message']}", 
          type: ConsoleMessageType.error);
      _stopServerMessagesPolling();
    }
    _updateConnectionStatus();
  });
}

// Basculer entre mode serveur et mode local
Future<void> _toggleServerMode(bool value) async {
  setState(() {
    _isServerMode = value;
  });

  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('switch_server_mode', value);

  if (!value) {
    setState(() {
      _serverConnected = false;
      _serverStatusMessage = 'Mode local activé';
    });
    _stopServerMessagesPolling();
    _updateConnectionStatus();
  } else {
    _testServerConnection();
  }
  
  _updateConnectionStatus();
  _addConsoleMessage(
    value ? "🔄 Activation du mode serveur..." : "🔄 Désactivation du mode serveur",
    type: ConsoleMessageType.info
  );
}

// Démarrer la récupération des messages serveur
void _startServerMessagesPolling() {
  _serverMessagesTimer?.cancel();
  _serverMessagesTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
    if (_isServerMode && _serverConnected) {
      _fetchServerMessages();
    }
  });
}

// Arrêter la récupération des messages
void _stopServerMessagesPolling() {
  _serverMessagesTimer?.cancel();
  _serverMessagesTimer = null;
}

// Récupérer les messages du serveur
Future<void> _fetchServerMessages() async {
  if (!_isServerMode || !_serverConnected) return;

  final result = await ServerBack.getMessages();
  
  setState(() {
    if (result['success'] == true) {
      final List<dynamic> newMessages = result['messages'] ?? [];
      
      for (var message in newMessages) {
        final String formattedMessage = _formatServerMessage(message);
        if (!_consoleMessages.any((cmd) => cmd.text.contains(formattedMessage))) {
          _addConsoleMessage("Serveur: $formattedMessage", 
              type: ConsoleMessageType.receive);
        }
      }
      
      _serverMessages = newMessages;
    } else {
      final errorMsg = result['message'] ?? 'Unknown error';
      _addConsoleMessage("Erreur récupération messages: $errorMsg", 
          type: ConsoleMessageType.error);
    }
  });
}

// Formater les messages serveur
String _formatServerMessage(dynamic message) {
  try {
    if (message is Map) {
      final deviceId = message['device_id']?.toString() ?? 'Inconnu';
      final messageText = message['message']?.toString() ?? 'Pas de message';
      final createdAt = message['created_at']?.toString() ?? '';
      
      String formattedDate = _formatServerDate(createdAt);
      
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

// Formater la date des messages serveur
String _formatServerDate(String isoDate) {
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
  void _listenToConnectionChanges() {
  _communicationService.globalConnectionStateStream.listen((isConnected) {
    if (mounted) {
      setState(() {
        _isActuallyConnected = isConnected;
        _connectionStatus = isConnected ? 'Connecté' : 'Déconnecté';
        _connectionStatusColor = isConnected ? Colors.green : Colors.red;
        _updateConnectionStatus();
      });
    }
  });

  _communicationService.bluetoothEnabledStream.listen((isEnabled) {
    _addConsoleMessage('Bluetooth est ${isEnabled ? 'activé' : 'désactivé'}.', type: ConsoleMessageType.info);
    if (mounted) setState(() {});
  });
}

  void _listenToReceivedData() {
    _communicationService.globalReceivedDataStream.listen((data) {
      if (mounted) {
        _addConsoleMessage("<<< RCV: $data");
      }
    });
  }

  Future<void> _checkInitialConnectivity() async {
    final bool isBluetoothEnabled = await _communicationService
        .isBluetoothEnabled();
    final bool isWifiConnected = await _communicationService.isWifiConnected();

    setState(() {
      _addConsoleMessage(
        'Vérification initiale: Bluetooth ${isBluetoothEnabled ? 'activé' : 'désactivé'}',
      );
      _addConsoleMessage(
        'Vérification initiale: Wi-Fi ${isWifiConnected ? 'connecté' : 'déconnecté'}',
      );
    });
  }

  void _updateConnectionStatus() {
  if (_isServerMode) {
    _connectionStatus = _serverConnected 
      ? "Connecté au serveur: ${ServerBack.activeBaseUrl}"
      : "Serveur non connecté";
    _connectionStatusColor = _serverConnected ? Colors.green : Colors.red;
  } else if (_isActuallyConnected) {
    if (_connectionType == ConnectionType.bluetooth && _connectedDeviceName != null) {
      _connectionStatus = "Connecté via Bluetooth à $_connectedDeviceName";
    } else if (_connectionType == ConnectionType.wifi && _connectedDeviceAddress != null) {
      _connectionStatus = "Connecté via Wi-Fi à $_connectedDeviceAddress";
    } else {
      _connectionStatus = "Connecté";
    }
    _connectionStatusColor = Colors.green;
  } else {
    _connectionStatus = "Déconnecté";
    _connectionStatusColor = Colors.red;
  }
  
  if (mounted) {
    setState(() {});
  }
}

  // Méthodes de connexion avec persistance
  Future<void> _connectToWifiDevice() async {
  // ⚠️ Utiliser les valeurs actuelles des contrôleurs, pas seulement les contrôleurs
  final String ip = _ipController.text.trim();
  final int? port = int.tryParse(_portController.text.trim());

  if (ip.isEmpty || port == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Fluttertoast.showToast(
        msg: "❌ IP/Port invalide",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    });
    return;
  }

  setState(() {
    _connectionStatus = "Connexion en cours...";
    _connectionStatusColor = Colors.orange;
  });

  final success = await _persistenceConnexion.connectWifi(ip, port, _wifiProtocol);
  
  if (success) {
    // Mettre à jour l'état réel de connexion
    _isActuallyConnected = true;
    
    // Ajouter à l'historique
    final deviceHistory = DeviceHistory(
      id: '$ip:$port',
      name: 'Appareil Wi-Fi',
      address: '$ip:$port',
      type: ConnectionType.wifi,
      lastConnected: DateTime.now(),
      protocol: _wifiProtocol,
    );
    await _deviceHistoryManager.addDeviceToHistory(deviceHistory);

    setState(() {
      _connectionStatus = 'Connecté';
      _connectionStatusColor = Colors.green;
      _connectionType = ConnectionType.wifi;
      _connectedDeviceName = 'Appareil Wi-Fi';
      _connectedDeviceAddress = '$ip:$port';
      _updateConnectionStatus();
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Fluttertoast.showToast(
        msg: "✅ Connecté avec succès!",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    });
  } else {
    _isActuallyConnected = false;
    setState(() {
      _connectionStatus = 'Déconnecté';
      _connectionStatusColor = Colors.red;
      _updateConnectionStatus();
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Fluttertoast.showToast(
        msg: "❌ Échec de connexion",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    });
  }
}

  Future<void> _connectToSelectedBluetoothDevice(
    BluetoothDevice device,
    BluetoothProtocol protocol,
  ) async {
    setState(() {
      _connectionStatus = "Connexion en cours...";
      _connectionStatusColor = Colors.orange;
    });

    final success = await _persistenceConnexion.connectBluetooth(
      device,
      protocol,
    );

    if (success) {
      // Ajouter à l'historique
      final deviceHistory = DeviceHistory(
        id: device.id,
        name: device.name,
        address: device.id,
        type: ConnectionType.bluetooth,
        lastConnected: DateTime.now(),
        protocol: protocol,
      );
      await _deviceHistoryManager.addDeviceToHistory(deviceHistory);

      setState(() {
        _connectionStatus = 'Connecté';
        _connectionStatusColor = Colors.green;
        _connectionType = ConnectionType.bluetooth;
        _selectedBluetoothDevice = device;
        _bluetoothProtocol = protocol;
        _connectedDeviceName = device.name;
        _connectedDeviceAddress = device.id;
        _updateConnectionStatus();
      });
      Fluttertoast.showToast(msg: "Connecté à ${device.name} !");
    } else {
      setState(() {
        _connectionStatus = 'Déconnecté';
        _connectionStatusColor = Colors.red;
        _updateConnectionStatus();
      });
      Fluttertoast.showToast(msg: "Échec de connexion Bluetooth");
    }
  }

  Future<void> _disconnectDevice() async {
  if (!_isActuallyConnected) {
    _addConsoleMessage("Aucun appareil connecté", type: ConsoleMessageType.warning);
    return;
  }
  
  _addConsoleMessage("Déconnexion de l'appareil...", type: ConsoleMessageType.info);
  try {
    _communicationService.disconnectAll();
    _persistenceConnexion.stopAutoReconnect();
    
    setState(() {
      _isActuallyConnected = false;
      _connectionStatus = 'Déconnecté';
      _connectionStatusColor = Colors.red;
      _connectedDeviceName = null;
      _connectedDeviceAddress = null;
      _updateConnectionStatus();
    });
    
    _addConsoleMessage("Déconnecté avec succès", type: ConsoleMessageType.success);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Fluttertoast.showToast(
        msg: "🔌 Déconnecté",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.orange,
        textColor: Colors.white,
      );
    });
  } catch (e) {
    _addConsoleMessage("Erreur lors de la déconnexion: ${e.toString()}", type: ConsoleMessageType.error);
  }
}

  // Nouvelle méthode pour afficher l'historique des appareils
  void _showDeviceHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Appareils récents', style: GoogleFonts.inter()),
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

  Widget _buildWifiHistoryList() {
    return FutureBuilder<List<DeviceHistory>>(
      future: _deviceHistoryManager.getDeviceHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Aucun appareil Wi-Fi récent'));
        }

        final wifiDevices = snapshot.data!
            .where((device) => device.type == ConnectionType.wifi)
            .toList();

        if (wifiDevices.isEmpty) {
          return const Center(child: Text('Aucun appareil Wi-Fi récent'));
        }

        return ListView.builder(
          itemCount: wifiDevices.length,
          itemBuilder: (context, index) {
            final device = wifiDevices[index];
            return ListTile(
              leading: const Icon(Icons.wifi, color: Colors.blue),
              title: Text(device.name),
              subtitle: Text(device.address),
              trailing: Text(_formatDate(device.lastConnected)),
              onTap: () {
                final parts = device.address.split(':');
                if (parts.length == 2) {
                  _ipController.text = parts[0];
                  _portController.text = parts[1];
                  _wifiProtocol =
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
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Aucun appareil Bluetooth récent'));
        }

        final bluetoothDevices = snapshot.data!
            .where((device) => device.type == ConnectionType.bluetooth)
            .toList();

        if (bluetoothDevices.isEmpty) {
          return const Center(child: Text('Aucun appareil Bluetooth récent'));
        }

        return ListView.builder(
          itemCount: bluetoothDevices.length,
          itemBuilder: (context, index) {
            final device = bluetoothDevices[index];
            return ListTile(
              leading: const Icon(Icons.bluetooth, color: Colors.blue),
              title: Text(
                device.name.isEmpty ? 'Appareil inconnu' : device.name,
              ),
              subtitle: Text(device.address),
              trailing: Text(_formatDate(device.lastConnected)),
              onTap: () {
                final bluetoothDevice = BluetoothDevice(
                  id: device.id,
                  name: device.name,
                  isBle: device.protocol == BluetoothProtocol.ble,
                );
                final protocol =
                    device.protocol as BluetoothProtocol? ??
                    BluetoothProtocol.classic;
                _connectToSelectedBluetoothDevice(bluetoothDevice, protocol);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _clearDeviceHistory() async {
    await _deviceHistoryManager.clearDeviceHistory();
    Fluttertoast.showToast(msg: "Historique des appareils effacé");
  }

  // Nouvelle méthode pour afficher les paramètres de persistance
  void _showPersistenceSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Paramètres de Persistance', style: GoogleFonts.inter()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPersistenceSettingRow(
                'Reconnexion automatique',
                _persistenceConnexion.autoConnectEnabled,
                (value) {
                  _persistenceConnexion.setAutoReconnect(value);
                  setState(() {});
                },
              ),
              const SizedBox(height: 16),
              _buildInfoCard('Statut actuel', _connectionStatus),
              const SizedBox(height: 16),
              _buildInfoCard(
                'Mode',
                _persistenceConnexion.lastConnectionMode ?? 'Aucun',
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                'Tentatives',
                '${_persistenceConnexion.reconnectAttempts}/${_persistenceConnexion.reconnectAttempts}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
          TextButton(
            onPressed: () {
              _persistenceConnexion.clearConnectionHistory();
              _clearDeviceHistory();
              Navigator.pop(context);
              Fluttertoast.showToast(msg: "Historique effacé");
            },
            child: const Text('Effacer tout'),
          ),
        ],
      ),
    );
  }

  Widget _buildPersistenceSettingRow(
    String title,
    bool value,
    Function(bool) onChanged,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: GoogleFonts.inter()),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildInfoCard(String title, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
   backgroundColor: Color.fromARGB(242, 255, 255, 255),
    appBar: AppBar(
      title: Text(
        _isServerMode && _serverConnected 
          ? 'Control Switch'
          : _connectionStatus == 'Connecté' && _connectedDeviceName != null
              ? 'Connecté à $_connectedDeviceName'
              : 'Switch Controller',
        style: GoogleFonts.interTight(
          fontWeight: FontWeight.w700,
          color: Color.fromARGB(240, 7, 7, 7),
        ),
      ),
      backgroundColor: Color.fromARGB(93, 226, 162, 13),
      centerTitle: true,
      actions: [
        // Bouton pour le mode serveur avec indicateur
        IconButton(
          icon: Stack(
            children: [
              Icon(
                Icons.cloud,
                color: _isServerMode 
                  ? (_serverConnected ? Colors.green : Colors.orange)
                  : Colors.white,
              ),
              if (_isServerMode && !_serverConnected)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          onPressed: _showServerConfigModal,
          tooltip: _isServerMode 
            ? (_serverConnected ? 'Serveur connecté' : 'Serveur déconnecté')
            : 'Configurer le mode serveur',
        ),
        
        // Autres boutons existants...
        IconButton(
          icon: const Icon(Icons.history, color: Colors.white),
          onPressed: _showDeviceHistoryDialog,
          tooltip: 'Historique des appareils',
        ),
          IconButton(
            icon: Icon(
              _connectionType == ConnectionType.wifi
                  ? Icons.wifi
                  : Icons.bluetooth,
              color: Colors.white,
            ),
            tooltip: 'Changer le mode de connexion',
            onPressed: _showConnectionTypeDialog,
          ),
          
          PopupMenuButton<String>(
            onSelected: _handleMenuSelection,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Mode édition')),
              const PopupMenuItem(
                value: 'advanced',
                child: Text('Paramètres avancés'),
              ),
              const PopupMenuItem(
                value: 'persistence',
                child: Text('Paramètres de persistance'),
              ),
              const PopupMenuItem(value: 'help', child: Text('Aide')),
              const PopupMenuItem(value: 'about', child: Text('À propos')),
            ],
          ),
        ],
      ),

      body: Stack(
        children: [
          Column(
            children: [
              // Barre de statut de connexion améliorée
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                color: _connectionStatusColor.withOpacity(0.15),
                child: Row(
                  children: [
                    Icon(
                      _connectionType == ConnectionType.wifi
                          ? Icons.wifi
                          : Icons.bluetooth,
                      size: 20,
                      color: _connectionStatusColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _connectionStatus,
                            style: TextStyle(
                              color: _connectionStatusColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          if (_connectedDeviceName != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _connectedDeviceName!,
                              style: TextStyle(
                                color: _connectionStatusColor.withOpacity(0.8),
                                fontSize: 14,
                              ),
                            ),
                          ],
                          if (_connectedDeviceAddress != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              _connectedDeviceAddress!,
                              style: TextStyle(
                                color: _connectionStatusColor.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_isActuallyConnected) ...[
                      IconButton(
                        icon: const Icon(
                          Icons.link_off,
                          color: Colors.red,
                          size: 20,
                        ),
                        onPressed: _disconnectDevice,
                        tooltip: 'Déconnecter',
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        color: _connectionStatusColor,
                        size: 20,
                      ),
                      onPressed: () {
                        if (_connectionType == ConnectionType.bluetooth) {
                          _showBluetoothDeviceSelection();
                        } else if (_connectionType == ConnectionType.wifi) {
                          _showWifiSetupDialog();
                        }
                      },
                      tooltip: 'Reconnecter',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      // Grille des switches (reste inchangée)
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount = constraints.maxWidth > 600
                                ? 3
                                : 2;
                            return GridView.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 2.7,
                                  ),
                              itemCount: _switchStates.length,
                              itemBuilder: (context, index) =>
                                  _buildSwitchCard(index),
                            );
                          },
                        ),
                      ),
                      _buildConsole(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Bouton déplaçable (reste inchangé)
          Positioned(
            left: _fabPosition.dx,
            top: _fabPosition.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _fabPosition = Offset(
                    _fabPosition.dx + details.delta.dx,
                    _fabPosition.dy + details.delta.dy,
                  );
                });
              },
              child: FloatingActionButton(
                onPressed: _addSwitch,
                child: const Icon(Icons.add),
                tooltip: 'Ajouter un switch',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Les méthodes existantes restent inchangées mais utilisent maintenant la persistance
  Widget _buildSwitchCard(int index) {
    final theme = Theme.of(context);
    final config = _switchConfigurations[index];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      config['name'],
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    'CMD: ${_switchStates[index] ? config['onCommand'] : config['offCommand']}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _switchStates[index] ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _switchStates[index],
              onChanged: (value) => _handleSwitchChange(index, value),
            ),
            PopupMenuButton<String>(
              onSelected: (value) => _handleSwitchMenu(index, value),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'rename', child: Text('Renommer')),
                const PopupMenuItem(
                  value: 'editCommands',
                  child: Text('Modifier commandes'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsole() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Console',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.clear_all),
                    onPressed: _clearConsole,
                    tooltip: 'Effacer la console',
                  ),
                  IconButton(
                    icon: Icon(
                      _showConsole ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: _toggleConsole,
                    tooltip: _showConsole
                        ? 'Masquer la console'
                        : 'Afficher la console',
                  ),
                ],
              ),
            ],
          ),
          if (_showConsole) const SizedBox(height: 6),
          if (_showConsole)
            Container(
              width: double.infinity,
              height: 200,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _consoleMessages.reversed.map((message) {
                    return _buildConsoleMessage(message);
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConsoleMessage(ConsoleMessage message) {
    Color textColor;

    switch (message.type) {
      case ConsoleMessageType.success:
        textColor = Colors.greenAccent;
        break;
      case ConsoleMessageType.warning:
        textColor = Colors.orangeAccent;
        break;
      case ConsoleMessageType.error:
        textColor = Colors.redAccent;
        break;
      case ConsoleMessageType.send:
        textColor = Colors.purpleAccent;
        break;
      case ConsoleMessageType.receive:
        textColor = Colors.cyanAccent;
        break;
      case ConsoleMessageType.system:
        textColor = Colors.grey;
        break;
      case ConsoleMessageType.info:
      default:
        textColor = Colors.white;
        break;
    }

    final timeString =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:'
        '${message.timestamp.minute.toString().padLeft(2, '0')}:'
        '${message.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '[$timeString] ',
              style: GoogleFonts.robotoMono(fontSize: 11, color: Colors.grey),
            ),
            TextSpan(
              text: message.text,
              style: GoogleFonts.robotoMono(fontSize: 13, color: textColor),
            ),
          ],
        ),
      ),
    );
  }

  void _clearConsole() {
    setState(() {
      _consoleMessages.clear();
      _addSystemMessage('Console effacée');
    });
  }

  void _showConnectionTypeDialog() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sélectionner le type de connexion'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() {
                _connectionType = ConnectionType.wifi;
              });
              Navigator.pop(context);
              _showWifiConnectionDialog();
            },
            child: const Row(
              children: [Icon(Icons.wifi), SizedBox(width: 8), Text('WiFi')],
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              setState(() {
                _connectionType = ConnectionType.bluetooth;
              });
              Navigator.pop(context);
              _showBluetoothConnectionDialog();
            },
            child: const Row(
              children: [
                Icon(Icons.bluetooth),
                SizedBox(width: 8),
                Text('Bluetooth'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showConnectionDialog() {
    if (_connectionType == ConnectionType.bluetooth) {
      _showBluetoothConnectionDialog();
    } else {
      _showWifiConnectionDialog();
    }
  }

  void _showBluetoothConnectionDialog() {
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
                          groupValue: _bluetoothProtocol,
                          onChanged: _isScanningBluetooth
                              ? null
                              : (value) {
                                  setStateInDialog(() {
                                    setState(() {
                                      _bluetoothProtocol = value!;
                                    });
                                  });
                                },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<BluetoothProtocol>(
                          title: Text('BLE', style: GoogleFonts.roboto()),
                          value: BluetoothProtocol.ble,
                          groupValue: _bluetoothProtocol,
                          onChanged: _isScanningBluetooth
                              ? null
                              : (value) {
                                  setStateInDialog(() {
                                    setState(() {
                                      _bluetoothProtocol = value!;
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
                            await _startBluetoothScan(setStateInDialog);
                          },
                    child: _isScanningBluetooth
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text('Recherche en cours...'),
                            ],
                          )
                        : const Text('Scanner les appareils'),
                  ),
                  const SizedBox(height: 20),

                  if (_discoveredBluetoothDevices.isNotEmpty)
                    Container(
                      height: 200,
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
                                    setStateInDialog(() {
                                      _selectedBluetoothDevice = value;
                                    });
                                  },
                          );
                        },
                      ),
                    ),

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

                  if (_discoveredBluetoothDevices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: ElevatedButton(
                        onPressed: _selectedBluetoothDevice == null
                            ? null
                            : () async {
                                await _connectToSelectedBluetoothDevice(
                                  _selectedBluetoothDevice!,
                                  _bluetoothProtocol,
                                );
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
              if (_connectionStatus == 'Connecté' &&
                  _connectionType == ConnectionType.bluetooth)
                TextButton(
                  onPressed: () async {
                    await _disconnectDevice();
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Déconnecter'),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showWifiConnectionDialog() {
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
                      groupValue: _wifiProtocol,
                      onChanged: (value) {
                        setState(() {
                          _wifiProtocol = value!;
                          _portController.text = '80';
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<WiFiProtocol>(
                      title: Text('WebSocket', style: GoogleFonts.roboto()),
                      value: WiFiProtocol.websocket,
                      groupValue: _wifiProtocol,
                      onChanged: (value) {
                        setState(() {
                          _wifiProtocol = value!;
                          _portController.text = '81';
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'Adresse IP',
                  hintText: 'Ex: 192.168.1.100',
                  prefixIcon: Icon(Icons.computer),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: 'Ex: 80',
                  prefixIcon: Icon(Icons.settings_input_svideo),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
          if (_connectionStatus == 'Connecté' &&
              _connectionType == ConnectionType.wifi)
            TextButton(
              onPressed: () async {
                await _disconnectDevice();
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Déconnecter'),
            ),
          ElevatedButton(
            onPressed: () {
              _connectToWifiDevice();
              Navigator.pop(context);
            },
            child: const Text('Connecter'),
          ),
        ],
      ),
    );
  }

  Future<void> _startBluetoothScan(StateSetter setStateInDialog) async {
    _addConsoleMessage(
      'Démarrage du scan Bluetooth (protocole: ${_bluetoothProtocol.name})...',
    );

    try {
      final bool isBluetoothOn = await _communicationService
          .isBluetoothEnabled();
      if (!isBluetoothOn) {
        _addConsoleMessage(
          'Bluetooth est désactivé. Tentative d\'activation...',
        );
        await _communicationService.setBluetoothEnabled(true);
        await Future.delayed(const Duration(seconds: 3));
        if (!await _communicationService.isBluetoothEnabled()) {
          _addConsoleMessage('Impossible d\'activer le Bluetooth. Abandon.');
          setStateInDialog(() {
            _isScanningBluetooth = false;
          });
          return;
        }
      }

      final foundDevices = await _communicationService.scanBluetoothDevices(
        protocol: _bluetoothProtocol,
        duration: 15,
      );

      setStateInDialog(() {
        _discoveredBluetoothDevices = foundDevices;
        _isScanningBluetooth = false;
      });

      if (foundDevices.isNotEmpty) {
        _addConsoleMessage(
          '${foundDevices.length} appareil(s) Bluetooth trouvé(s).',
        );
        for (final device in foundDevices) {
          final deviceName = device.name.isNotEmpty
              ? device.name
              : 'Appareil inconnu';
          _addConsoleMessage('  - $deviceName (${device.id})');
        }
      } else {
        _addConsoleMessage('Aucun appareil Bluetooth trouvé.');
      }
    } catch (e) {
      _addConsoleMessage('Erreur lors du scan Bluetooth: ${e.toString()}');
      setStateInDialog(() {
        _isScanningBluetooth = false;
      });
    }
  }

  // Les méthodes existantes pour la gestion des switches restent inchangées
  void _handleSwitchChange(int index, bool value) async {
  final config = _switchConfigurations[index];
  final command = value ? config['onCommand'] : config['offCommand'];
  
  setState(() {
    _switchStates[index] = value;
    config['lastToggleTime'] = DateTime.now();
    _addConsoleMessage('Switch "${config['name']}" -> $command', type: ConsoleMessageType.info);
  });

  // ⚠️ CORRECTION : Utiliser _displayConnected au lieu de _isActuallyConnected
  if (_displayConnected) { // <-- CHANGEMENT ICI
    try {
      await _sendCommandToDevice(command);
      
      Future.delayed(const Duration(milliseconds: 500), () {
        _addConsoleMessage('Commande "$command" exécutée avec succès', type: ConsoleMessageType.success);
      });
    } catch (e) {
      _addConsoleMessage('Erreur envoi commande: ${e.toString()}', type: ConsoleMessageType.error);
    }
  } else {
    _addConsoleMessage('Appareil non connecté - commande non envoyée', type: ConsoleMessageType.warning);
    
    // Afficher un toast d'erreur
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Fluttertoast.showToast(
        msg: "❌ Aucun appareil connecté",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    });
    
    // Revenir à l'état précédent
    setState(() {
      _switchStates[index] = !value;
    });
  }
}

  Future<void> _sendCommandToDevice(String command) async {
  try {
    if (_isServerMode) {
      // Envoi via le serveur
      if (!_serverConnected) {
        _addConsoleMessage("❌ Serveur non connecté", type: ConsoleMessageType.error);
        return;
      }
      
      final result = await ServerBack.sendCommand(command);
      
      if (result['success'] == true) {
        _addConsoleMessage("Commande envoyée au serveur: '$command'", 
            type: ConsoleMessageType.send);
        _addConsoleMessage("Réponse serveur: ${result['message']}", 
            type: ConsoleMessageType.receive);
      } else {
        _addConsoleMessage("Erreur serveur: ${result['message']}", 
            type: ConsoleMessageType.error);
      }
    } else {
      // Envoi local (code existant)
      if (_connectionType == ConnectionType.bluetooth) {
        await _communicationService.sendBluetoothCommand(command);
        _addConsoleMessage('Commande Bluetooth envoyée: "$command"', 
            type: ConsoleMessageType.send);
      } else if (_connectionType == ConnectionType.wifi) {
        final String ip = _currentIP;
        final int? port = _currentPort;

        if (ip.isEmpty || port == null) {
          throw Exception('Adresse IP ou port Wi-Fi invalide pour l\'envoi de commande.');
        }

        if (_wifiProtocol == WiFiProtocol.http) {
          _addConsoleMessage('Tentative d\'envoi HTTP à $ip:$port : "$command"', 
              type: ConsoleMessageType.send);
          
          final result = await _communicationService.sendHttpCommand(
            ip: ip,
            port: port,
            command: command,
          );

          if (result.success) {
            _addConsoleMessage('Requête HTTP envoyée. Réponse: ${result.message}', 
                type: ConsoleMessageType.receive);
          } else {
            _addConsoleMessage('Erreur lors de l\'envoi HTTP: ${result.message}', 
                type: ConsoleMessageType.error);
          }
        } else if (_wifiProtocol == WiFiProtocol.websocket) {
          _communicationService.sendWebSocketMessage(command);
          _addConsoleMessage('Message WebSocket envoyé: "$command"', 
              type: ConsoleMessageType.send);
        }
      }
    }
  } catch (e) {
    _addConsoleMessage('Erreur lors de l\'envoi de la commande: ${e.toString()}', 
        type: ConsoleMessageType.error);
    rethrow;
  }
}

  // Afficher la configuration serveur
void _showServerConfigModal() {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        width: MediaQuery.of(context).size.width * 0.75,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(blurRadius: 20, color: Colors.black.withOpacity(0.3)),
          ],
        ),
        child: Column(
          children: [
            // Header avec bouton de fermeture
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Paramètres du Serveur',
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fermer',
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildServerTab(),
            ),
          ],
        ),
      ),
    ),
  );
}

// Onglet serveur dans les paramètres
Widget _buildServerTab() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Switch pour activer le mode serveur
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.cloud, color: _isServerMode ? Colors.blue : Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mode Serveur',
                            style: GoogleFonts.inter(color: Colors.black),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          Text(
                            _isServerMode ? 'Activé' : 'Désactivé',
                            style: GoogleFonts.inter(
                              color: _isServerMode ? Colors.green : Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isServerMode,
                onChanged: (bool value) async {
                  await _toggleServerMode(value);
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Statut de connexion au serveur
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _serverConnected ? Colors.green[50] : Colors.orange[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _serverConnected ? Colors.green : Colors.orange,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _serverConnected ? Icons.cloud_done : Icons.cloud_off,
                color: _serverConnected ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _serverStatusMessage,
                  style: TextStyle(
                    color: _serverConnected ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Bouton pour tester la connexion
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.cloud_upload, color: Colors.white),
            label: const Text('Tester la connexion serveur'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _testServerConnection,
          ),
        ),
        const SizedBox(height: 16),

        // Bouton pour ouvrir la configuration serveur complète
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: Icon(Icons.settings, color: Theme.of(context).primaryColor),
            label: Text(
              'Configuration du serveur',
              style: TextStyle(color: Theme.of(context).primaryColor),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).primaryColor,
              side: BorderSide(color: Theme.of(context).primaryColor),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _showFullServerConfigModal,
          ),
        ),
        const SizedBox(height: 16),
        
        // Bouton Fermer
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey,
              side: const BorderSide(color: Colors.grey),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Fermer'),
          ),
        ),
      ],
    ),
  );
}

// Configuration serveur complète
void _showFullServerConfigModal() {
  Navigator.of(context).pop(); // Fermer le modal actuel
  
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        width: MediaQuery.of(context).size.width * 0.9,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(blurRadius: 20, color: Colors.black.withOpacity(0.3)),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Configuration du Serveur',
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fermer',
                  ),
                ],
              ),
            ),
            Expanded(
              child: ServerFront(), // Votre widget ServerFront complet
            ),
          ],
        ),
      ),
    ),
  );
}

  void _toggleConsole() {
    setState(() {
      _showConsole = !_showConsole;
    });
  }

  void _addSwitch() {
    setState(() {
      final newIndex = _switchStates.length;
      _switchStates.add(false);
      _switchConfigurations.add({
        'name': 'Switch ${newIndex + 1}',
        'onCommand': 'ON',
        'offCommand': 'OFF',
        'lastToggleTime': DateTime.now(),
      });
      _addConsoleMessage('Nouveau switch ajouté.');
    });
  }

  void _handleMenuSelection(String value) {
  switch (value) {
    case 'edit':
      _showEditAllSwitchesDialog();
      break;
    case 'advanced':
      _showAdvancedDialog();
      break;
    // ⚠️ AJOUTER CE CAS
    case 'persistence':
      _showPersistenceSettings();
      break;
    case 'help':
      _showHelpDialog();
      break;
    case 'about':
      _showAboutDialog();
      break;
  }
}

  void _handleSwitchMenu(int index, String value) {
    switch (value) {
      case 'rename':
        _showRenameDialog(index);
        break;
      case 'editCommands':
        _showEditCommandsDialog(index);
        break;
      case 'delete':
        _deleteSwitch(index);
        break;
    }
  }

  void _showRenameDialog(int index) {
    final config = _switchConfigurations[index];
    final controller = TextEditingController(text: config['name']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer le switch'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nom du switch'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                config['name'] = controller.text;
                _addConsoleMessage('Switch renommé en "${controller.text}"');
              });
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showEditAllSwitchesDialog() {
    List<Map<String, TextEditingController>> controllers = _switchConfigurations
        .map(
          (config) => {
            'name': TextEditingController(text: config['name']),
            'onCommand': TextEditingController(text: config['onCommand']),
            'offCommand': TextEditingController(text: config['offCommand']),
          },
        )
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Éditer tous les switches'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: _switchConfigurations.length,
            itemBuilder: (context, index) {
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controllers[index]['name']!,
                              decoration: const InputDecoration(
                                labelText: 'Nom du switch',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              Navigator.pop(context);
                              _deleteSwitch(index);
                              _showEditAllSwitchesDialog();
                            },
                            tooltip: 'Supprimer ce switch',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controllers[index]['onCommand']!,
                              decoration: const InputDecoration(
                                labelText: 'Commande ON',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: controllers[index]['offCommand']!,
                              decoration: const InputDecoration(
                                labelText: 'Commande OFF',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                for (int i = 0; i < _switchConfigurations.length; i++) {
                  _switchConfigurations[i]['name'] =
                      controllers[i]['name']!.text;
                  _switchConfigurations[i]['onCommand'] =
                      controllers[i]['onCommand']!.text.isEmpty
                      ? 'ON'
                      : controllers[i]['onCommand']!.text;
                  _switchConfigurations[i]['offCommand'] =
                      controllers[i]['offCommand']!.text.isEmpty
                      ? 'OFF'
                      : controllers[i]['offCommand']!.text;
                }
                _addConsoleMessage('Tous les switches ont été mis à jour');
              });
              Navigator.pop(context);
            },
            child: const Text('Sauvegarder'),
          ),
        ],
      ),
    );
  }

  void _showEditCommandsDialog(int index) {
    final config = _switchConfigurations[index];
    final onController = TextEditingController(text: config['onCommand']);
    final offController = TextEditingController(text: config['offCommand']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier les commandes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: onController,
              decoration: const InputDecoration(
                labelText: 'Commande ON',
                hintText: 'Ex: ALLUMER, START, 1...',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: offController,
              decoration: const InputDecoration(
                labelText: 'Commande OFF',
                hintText: 'Ex: ETEINDRE, STOP, 0...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                config['onCommand'] = onController.text.isEmpty
                    ? 'ON'
                    : onController.text;
                config['offCommand'] = offController.text.isEmpty
                    ? 'OFF'
                    : offController.text;
                _addConsoleMessage(
                  'Commandes modifiées pour "${config['name']}" : ${config['onCommand']} / ${config['offCommand']}',
                );
              });
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAdvancedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paramètres avancés'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Informations de connexion:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Mode: ${_connectionType == ConnectionType.wifi ? "WiFi" : "Bluetooth"}',
            ),
            if (_connectionType == ConnectionType.wifi)
              Text('Protocole WiFi: ${_wifiProtocol.name}')
            else
              Text('Protocole Bluetooth: ${_bluetoothProtocol.name}'),
            Text('Statut: $_connectionStatus'),
            if (_connectedDeviceName != null)
              Text('Appareil: $_connectedDeviceName'),
            const SizedBox(height: 16),
            const Text(
              'Ici, vous pouvez ajouter d\'autres paramètres avancés.',
            ),
          ],
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

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aide'),
        content: const SingleChildScrollView(
          child: Text(
            'Utilisez cette interface pour contrôler vos switches ESP32.\n\n'
            '🔹 Connexions:\n'
            '• Bluetooth: Scannez et connectez-vous aux appareils BLE ou Classic\n'
            '• WiFi: Connectez-vous via HTTP ou WebSocket en saisissant IP:Port\n\n'
            '🔹 Utilisation:\n'
            '• Appuyez sur un switch pour le basculer ON/OFF\n'
            '• Utilisez le menu ⋮ pour personnaliser chaque switch\n'
            '• Modifiez les commandes ON/OFF selon vos besoins\n'
            '• Consultez la console pour voir les échanges de données\n\n'
            '🔹 Persistance:\n'
            '• La connexion est automatiquement restaurée au redémarrage\n'
            '• Historique des appareils disponibles via le bouton 📚\n'
            '• Reconnexion automatique en cas de perte de connexion\n\n'
            '🔹 Statut:\n'
            '• La barre colorée indique l\'état de connexion\n'
            '• Vert = Connecté, Rouge = Déconnecté, Orange = Connexion en cours',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('À propos'),
        content: const Text(
          'Application ESP32 IoT Switch Controller\n'
          'Version 2.0 avec Persistance\n\n'
          'Contrôlez vos appareils ESP32 via Bluetooth ou WiFi\n'
          'avec une interface intuitive et personnalisable.\n\n'
          'Fonctionnalités:\n'
          '• Connexion automatique et persistance\n'
          '• Historique des appareils connectés\n'
          '• Reconnexion automatique\n'
          '• Interface moderne et responsive',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _deleteSwitch(int index) {
    setState(() {
      _addConsoleMessage(
        'Switch "${_switchConfigurations[index]['name']}" supprimé.',
      );
      _switchStates.removeAt(index);
      _switchConfigurations.removeAt(index);
    });
  }

  void _showWifiSetupDialog() {
    // Ouvre le dialogue WiFi pour reconfiguration
    _showWifiConnectionDialog();
  }

  void _showBluetoothDeviceSelection() {
    // Ouvre le dialogue Bluetooth pour reconfiguration
    _showBluetoothConnectionDialog();
  }
}

// Ajoutez cette classe en haut du fichier
enum ConsoleMessageType {
  info, // Bleu - informations générales
  success, // Vert - succès
  warning, // Orange - avertissements
  error, // Rouge - erreurs
  send, // Violet - messages envoyés
  receive, // Cyan - messages reçus
  system, // Gris - messages système
}

class ConsoleMessage {
  final String text;
  final ConsoleMessageType type;
  final DateTime timestamp;

  ConsoleMessage(this.text, this.type, this.timestamp);
}
