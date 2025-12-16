import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:claude_iot/services/services.commun.dart' hide CommunicationMode;
import 'package:claude_iot/services/services.bluetooth.dart';
import 'package:claude_iot/utils/persistence_connexion.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:claude_iot/commande/pwmParametre.dart';
import 'package:claude_iot/server/server_back.dart';
import 'package:claude_iot/server/server_front.dart';
import 'dart:async';
import 'dart:convert';

// Enums et classes de base
enum ConnectionMode { none, bluetooth, wifi }

enum ConnectionStatus { deconnected, connecting, connected }

class DeviceHistory {
  final String id;
  final String name;
  final String address;
  final ConnectionMode mode;
  final DateTime lastConnected;
  final dynamic protocol;

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
  static const String _storageKey = 'pwm_device_history';
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

class PWMControllerScreen extends StatefulWidget {
  const PWMControllerScreen({super.key});

  @override
  State<PWMControllerScreen> createState() => _PWMControllerScreenState();
}

class ConsoleMessage {
  final String text;
  final String timestamp;
  final String type; // 'info', 'success', 'error', 'warning', 'send', 'receive'

  ConsoleMessage({
    required this.text,
    required this.timestamp,
    required this.type,
  });

  Color get color {
    switch (type) {
      case 'success':
        return Colors.green;
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'send':
        return Colors.blue;
      case 'receive':
        return Colors.purple;
      default: // info
        return Colors.grey[700]!;
    }
  }

  IconData get icon {
    switch (type) {
      case 'success':
        return Icons.check_circle;
      case 'error':
        return Icons.error;
      case 'warning':
        return Icons.warning;
      case 'send':
        return Icons.arrow_upward;
      case 'receive':
        return Icons.arrow_downward;
      default:
        return Icons.info;
    }
  }
}

class _PWMControllerScreenState extends State<PWMControllerScreen>
    with WidgetsBindingObserver {
  // Liste des canaux PWM
  final List<PWMChannel> _pwmChannels = [
    PWMChannel(
      id: 1,
      name: 'LED 1',
      icon: Icons.lightbulb_outline,
      minValue: 0,
      maxValue: 255,
      currentValue: 0,
      pin: 2,
      frequency: 1000,
      resolution: 8,
      sendFrequency: false, // Désactivé par défaut
      sendResolution: false, // Désactivé par défaut
    ),
    PWMChannel(
      id: 2,
      name: 'LED 2',
      icon: Icons.lightbulb_outline,
      minValue: 0,
      maxValue: 255,
      currentValue: 0,
      pin: 4,
      frequency: 1000,
      resolution: 8,
      sendFrequency: false,
      sendResolution: false,
    ),
    PWMChannel(
      id: 3,
      name: 'LED 3',
      icon: Icons.lightbulb_outline,
      minValue: 0,
      maxValue: 255,
      currentValue: 0,
      pin: 5,
      frequency: 1000,
      resolution: 8,
      sendFrequency: false,
      sendResolution: false,
    ),
    PWMChannel(
      id: 4,
      name: 'LED 4',
      icon: Icons.lightbulb_outline,
      minValue: 0,
      maxValue: 255,
      currentValue: 0,
      pin: 12,
      frequency: 1000,
      resolution: 8,
      sendFrequency: false,
      sendResolution: false,
    ),
    PWMChannel(
      id: 5,
      name: 'Moteur 1',
      icon: Icons.settings,
      minValue: 0,
      maxValue: 255,
      currentValue: 0,
      pin: 13,
      frequency: 500,
      resolution: 8,
      sendFrequency: false,
      sendResolution: false,
    ),
    PWMChannel(
      id: 6,
      name: 'Moteur 2',
      icon: Icons.settings,
      minValue: 0,
      maxValue: 255,
      currentValue: 10,
      pin: 14,
      frequency: 500,
      resolution: 8,
      sendFrequency: false,
      sendResolution: false,
    ),
    PWMChannel(
      id: 7,
      name: 'Joystick',
      icon: Icons.gamepad,
      minValue: 0,
      maxValue: 255,
      currentValue: 0,
      pin: 15,
      frequency: 60,
      resolution: 8,
      sendFrequency: false,
      sendResolution: false,
    ),
    PWMChannel(
      id: 8,
      name: 'Ventilateur',
      icon: Icons.toys,
      minValue: 0,
      maxValue: 255,
      currentValue: 10,
      pin: 16,
      frequency: 250,
      resolution: 8,
      sendFrequency: false,
      sendResolution: false,
    ),
  ];

  // Gestion de la connexion
  late PersistenceConnexion _persistenceConnexion;
  final DeviceHistoryManager _deviceHistoryManager = DeviceHistoryManager();
  final CommunicationService _communicationService = CommunicationService();

  // État de connexion
  ConnectionMode _connectionMode = ConnectionMode.none;
  ConnectionStatus _connectionStatus = ConnectionStatus.deconnected;
  String _connectedDevice = '';
  String? _connectedDeviceName;

  // Bluetooth
  List<BluetoothDevice> _discoveredBluetoothDevices = [];
  BluetoothDevice? _selectedBluetoothDevice;
  bool _isScanningBluetooth = false;
  BluetoothProtocol _bluetoothProtocolMode = BluetoothProtocol.classic;

  // Wi-Fi
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '81',
  );
  final TextEditingController _manualCommandController =
      TextEditingController();

  final List<String> _commandHistory = [];
  WiFiProtocol _wifiProtocolMode = WiFiProtocol.http;

  // Console
  bool _showConsole = false;
  final List<ConsoleMessage> _consoleMessages = [];
  final ScrollController _consoleScrollController = ScrollController();

  // Mode édition PWM
  bool _editMode = true;
  int? _selectedChannelIndex;

  // Variables pour le mode serveur (AJOUT)
  bool _isServerMode = false;
  bool _serverConnected = false;
  String _serverStatusMessage = 'Non connecté au serveur';
  Timer? _serverMessagesTimer;
  List<dynamic> _serverMessages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePersistenceConnexion();
    _communicationService.initialize();
    _listenToConnectionChanges();
    _listenToReceivedData();
    _loadServerSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistenceConnexion.dispose();
    _manualCommandController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _consoleScrollController.dispose();
    _communicationService.dispose();
    _serverMessagesTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRestoreConnection();
    }
  }

  void _initializePersistenceConnexion() {
    _persistenceConnexion = PersistenceConnexion(
      onLogMessage: (message) {
        _addConsoleMessage(message);
      },
      onConnectionStatusChanged: (connected) {
        setState(() {
          _connectionStatus = connected
              ? ConnectionStatus.connected
              : ConnectionStatus.deconnected;
        });
      },
      onReconnectStarted: () {
        _addConsoleMessage(
          "🔄 Connexion auto en cours...",
          type: 'info',
        );
      },
      // CORRECTION ICI - Ajoutez le 3ème paramètre
      onReconnectSuccess: (ip, port, microcontrollerType) {
        _addConsoleMessage(
          "✅ Reconnexion Wi-Fi réussie à $ip:$port",
          type: 'success',
        );
        setState(() {
          _connectionStatus = ConnectionStatus.connected;
          _connectedDevice = "$ip:$port";
        });
      },
      onBluetoothReconnectSuccess: (device) {
        _addConsoleMessage(
          "✅ Reconnexion Bluetooth réussie à ${device.name}",
          type: 'success',
        );
        setState(() {
          _connectionStatus = ConnectionStatus.connected;
          _connectedDeviceName = device.name;
          _connectedDevice = "${device.name} (${device.id})";
        });
      },
      onReconnectFailed: (error) {
        _addConsoleMessage("❌ Échec reconnexion: $error");
      },
      communicationService: _communicationService,
    );

    _persistenceConnexion.initialize().then((_) {
      _attemptAutoReconnectOnStartup();
    });
  }

  void _listenToConnectionChanges() {
    _communicationService.globalConnectionStateStream.listen((isConnected) {
      if (!isConnected && _connectionStatus == ConnectionStatus.connected) {
        _addConsoleMessage("⚡ Déconnexion détectée", type: 'error');
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
  }

  void _listenToReceivedData() {
    _communicationService.globalReceivedDataStream.listen((data) {
      _addConsoleMessage("<<< RCV: $data", type: 'receive');
    });
  }

  void _sendManualCommand() {
    if (_connectionStatus != ConnectionStatus.connected) {
      _addConsoleMessage(
        "❌ Impossible d'envoyer la commande - Non connecté",
        type: 'error',
      );
      Fluttertoast.showToast(msg: "Connectez-vous d'abord à un appareil");
      return;
    }

    final command = _manualCommandController.text.trim();
    if (command.isEmpty) return;

    _addConsoleMessage(">>> Commande manuelle: $command", type: 'send');

    if (!_commandHistory.contains(command)) {
      _commandHistory.add(command);
      if (_commandHistory.length > 10) {
        _commandHistory.removeAt(0);
      }
    }

    _sendRawCommand(command);

    _manualCommandController.clear();
  }

  void _showCommandHistory() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Historique des commandes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _commandHistory.isEmpty
                  ? Center(
                      child: Text(
                        'Aucune commande dans l\'historique',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _commandHistory.length,
                      itemBuilder: (context, index) {
                        final command = _commandHistory.reversed
                            .toList()[index];
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(command),
                          onTap: () {
                            _manualCommandController.text = command;
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<ConsoleMessage> get _filteredConsoleMessages {
    if (_consoleFilter == 'all') {
      return _consoleMessages;
    }
    return _consoleMessages
        .where((message) => message.type == _consoleFilter)
        .toList();
  }

  // Add this method to copy messages to clipboard
  void _copyMessageToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    Fluttertoast.showToast(msg: "Message copié dans le presse-papier");
  }

  // === MÉTHODES SERVEUR (AJOUT) ===

  Future<void> _loadServerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isServerMode = prefs.getBool('pwm_server_mode') ?? false;
    });

    if (_isServerMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _testServerConnection();
      });
    }
  }

  Future<void> _testServerConnection() async {
    setState(() {
      _serverStatusMessage = 'Test de connexion au serveur...';
    });

    final result = await ServerBack.checkServerStatus();

    setState(() {
      _serverConnected = result['success'] ?? false;
      _serverStatusMessage = result['message'] ?? 'Erreur inconnue';

      if (_serverConnected) {
        _addConsoleMessage(
          "✅ Connecté au : ${ServerBack.activeBaseUrl}",
          type: 'success',
        );
        _startServerMessagesPolling();
        _fetchServerMessages();
      } else {
        _addConsoleMessage(
          "❌ Erreur serveur: ${result['message']}",
          type: 'error',
        );
        _stopServerMessagesPolling();
      }
    });
  }

  Future<void> _toggleServerMode(bool value) async {
    setState(() {
      _isServerMode = value;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pwm_server_mode', value);

    if (!value) {
      setState(() {
        _serverConnected = false;
        _serverStatusMessage = 'Mode local activé';
      });
      _stopServerMessagesPolling();
    } else {
      _testServerConnection();
    }

    _addConsoleMessage(
      value
          ? "🔄 Activation du mode serveur..."
          : "🔄 Désactivation du mode serveur",
      type: 'info',
    );
  }

  void _startServerMessagesPolling() {
    _serverMessagesTimer?.cancel();
    _serverMessagesTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      if (_isServerMode && _serverConnected) {
        _fetchServerMessages();
      }
    });
  }

  void _stopServerMessagesPolling() {
    _serverMessagesTimer?.cancel();
    _serverMessagesTimer = null;
  }

  Future<void> _fetchServerMessages() async {
    if (!_isServerMode || !_serverConnected) return;

    final result = await ServerBack.getMessages();

    setState(() {
      if (result['success'] == true) {
        final List<dynamic> newMessages = result['messages'] ?? [];

        for (var message in newMessages) {
          final String formattedMessage = _formatServerMessage(message);
          if (!_consoleMessages.any(
            (msg) => msg.text.contains(formattedMessage),
          )) {
            _addConsoleMessage("Serveur: $formattedMessage", type: 'receive');
          }
        }

        _serverMessages = newMessages;
      } else {
        final errorMsg = result['message'] ?? 'Unknown error';
        _addConsoleMessage(
          "Erreur récupération messages: $errorMsg",
          type: 'error',
        );
      }
    });
  }

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

  void _showServerConfigModal() {
    showDialog(
      context: context,
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
                      icon: const Icon(
                        Icons.close,
                        color: Colors.black,
                        size: 24,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Fermer',
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildServerTab()),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullServerConfigModal() {
    Navigator.of(context).pop(); // Fermer le modal actuel

    showDialog(
      context: context,
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
                      icon: const Icon(
                        Icons.close,
                        color: Colors.black,
                        size: 24,
                      ),
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
                    Icon(
                      Icons.cloud,
                      color: _isServerMode ? Colors.blue : Colors.grey,
                    ),
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
                              color: _isServerMode
                                  ? Colors.green
                                  : Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              StatefulBuilder(
                builder: (context, setStateModal) {
                  return Switch(
                    value: _isServerMode,
                    onChanged: (bool value) async {
                      setStateModal(() {});
                      await _toggleServerMode(value);
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  );
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _serverStatusMessage,
                      style: TextStyle(
                        color: _serverConnected ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_serverConnected)
                      Text(
                        ServerBack.activeBaseUrl,
                        style: TextStyle(
                          color: _serverConnected ? Colors.green : Colors.orange,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                  ],
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
            icon: Icon(Icons.cloud_upload, color: Colors.white),
            label: Text('Tester la connexion serveur'),
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

        // NOUVEAU : Paramètres supplémentaires du serveur
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paramètres supplémentaires',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              
              // Reconnexion automatique
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.autorenew, size: 20, color: Colors.grey[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Connexion auto',
                        style: GoogleFonts.inter(color: Colors.black),
                      ),
                    ],
                  ),
                  Switch(
                    value: _persistenceConnexion.autoConnectEnabled,
                    onChanged: (bool value) {
                      setState(() {
                        _persistenceConnexion.autoConnectEnabled ;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Console de débogage
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.terminal, size: 20, color: Colors.grey[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Console débogage',
                        style: GoogleFonts.inter(color: Colors.black),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                  Switch(
                    value: _showConsole,
                    onChanged: (bool value) {
                      setState(() {
                        _showConsole = value;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Bouton pour ouvrir la configuration serveur complète
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: Icon(Icons.settings, color: Theme.of(context).primaryColor),
            label: Text(
              'Configuration avancée du serveur',
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
            child: Text('Fermer'),
          ),
        ),
      ],
    ),
  );
}
  // MODIFIER _sendRawCommand pour supporter le serveur
  Future<void> _sendRawCommand(String command) async {
    if (_isServerMode) {
      if (!_serverConnected) {
        _addConsoleMessage(
          "❌ Serveur non connecté - Commande non envoyée",
          type: 'error',
        );
        Fluttertoast.showToast(msg: "Connectez-vous d'abord au serveur");
        return;
      }

      try {
        final result = await ServerBack.sendCommand(command);
        if (result['success'] == true) {
          _addConsoleMessage(
            "✅ Commande envoyée au serveur: '$command'",
            type: 'send',
          );
          _addConsoleMessage(
            "Réponse serveur: ${result['message']}",
            type: 'receive',
          );
        } else {
          _addConsoleMessage(
            "❌ Erreur serveur: ${result['message']}",
            type: 'error',
          );
        }
      } catch (e) {
        _addConsoleMessage("❌ Erreur: ${e.toString()}", type: 'error');
      }
    } else {
      // Code existant pour Bluetooth/Wi-Fi
      if (_connectionStatus != ConnectionStatus.connected) {
        _addConsoleMessage(
          "❌ Aucun appareil connecté - Commande non envoyée",
          type: 'error',
        );
        Fluttertoast.showToast(msg: "Connectez-vous d'abord à un appareil");
        return;
      }

      try {
        if (_connectionMode == ConnectionMode.bluetooth) {
          await _communicationService.sendBluetoothCommand(command);
          _addConsoleMessage("✅ Commande Bluetooth envoyée", type: 'success');
        } else if (_connectionMode == ConnectionMode.wifi) {
          if (_wifiProtocolMode == WiFiProtocol.http) {
            final result = await _communicationService.sendHttpCommand(
              ip: _ipController.text.trim(),
              port: int.parse(_portController.text.trim()),
              command: command,
            );

            if (result.success) {
              _addConsoleMessage(
                "✅ Réponse HTTP: ${result.message}",
                type: 'success',
              );
            } else {
              _addConsoleMessage(
                "❌ Erreur HTTP: ${result.message}",
                type: 'error',
              );
              if (result.message.contains("connect") ||
                  result.message.contains("timeout")) {
                setState(() {
                  _connectionStatus = ConnectionStatus.deconnected;
                });
              }
            }
          } else {
            _communicationService.sendWebSocketMessage(command);
            _addConsoleMessage("✅ Commande WebSocket envoyée", type: 'success');
          }
        }
      } catch (e) {
        _addConsoleMessage("❌ Erreur: ${e.toString()}", type: 'error');
        setState(() {
          _connectionStatus = ConnectionStatus.deconnected;
        });
      }
    }
  }

  // MODIFIER _sendPWMCommand pour supporter le serveur
  Future<void> _sendPWMCommand(
    int pin,
    int value,
    int frequency,
    int resolution,
    bool sendFrequency,
    bool sendResolution,
  ) async {
    if (_isServerMode) {
      if (!_serverConnected) {
        _addConsoleMessage(
          "❌ Serveur non connecté. Impossible d'envoyer la commande PWM.",
          type: 'error',
        );
        Fluttertoast.showToast(msg: "Connectez-vous d'abord au serveur");
        return;
      }
    } else if (_connectionStatus != ConnectionStatus.connected) {
      _addConsoleMessage(
        "❌ Aucun appareil connecté. Impossible d'envoyer la commande PWM.",
        type: 'error',
      );
      Fluttertoast.showToast(msg: "Connectez-vous d'abord à un appareil");
      return;
    }

    try {
      // Format simplifié par défaut : P5:255
      String command;

      if (sendFrequency && sendResolution) {
        // Format complet : P5:255:1000:8
        command = "P$pin:$value:$frequency:$resolution";
      } else if (sendFrequency) {
        // Avec fréquence seulement : P5:255:1000
        command = "P$pin:$value:$frequency";
      } else if (sendResolution) {
        // Avec résolution seulement : P5:255::8
        command = "P$pin:$value::$resolution";
      } else {
        // Format simple par défaut : P5:255
        command = "P$pin:$value";
      }

      // Format alternatif si nécessaire pour le Wi-Fi HTTP
      if (!_isServerMode &&
          _connectionMode == ConnectionMode.wifi &&
          _wifiProtocolMode == WiFiProtocol.http) {
        command = command.replaceAll(':', ',');
      }

      if (_isServerMode) {
        // Envoi via serveur
        final result = await ServerBack.sendCommand(command);
        if (result['success'] == true) {
          _addConsoleMessage(
            "✅ Commande PWM envoyée au serveur: $command",
            type: 'send',
          );
          _addConsoleMessage(
            "Réponse serveur: ${result['message']}",
            type: 'receive',
          );
        } else {
          _addConsoleMessage(
            "❌ Erreur serveur: ${result['message']}",
            type: 'error',
          );
        }
      } else {
        // Envoi local (code existant)
        if (_connectionMode == ConnectionMode.bluetooth) {
          await _communicationService.sendBluetoothCommand(command);
        } else if (_connectionMode == ConnectionMode.wifi) {
          if (_wifiProtocolMode == WiFiProtocol.http) {
            final result = await _communicationService.sendHttpCommand(
              ip: _ipController.text.trim(),
              port: int.parse(_portController.text.trim()),
              command: command,
            );

            if (!result.success) {
              _addConsoleMessage(
                "❌ Erreur HTTP: ${result.message}",
                type: 'error',
              );
              if (result.message.contains("connect") ||
                  result.message.contains("timeout")) {
                setState(() {
                  _connectionStatus = ConnectionStatus.deconnected;
                });
              }
              return;
            }
          } else {
            _communicationService.sendWebSocketMessage(command);
          }
        }
        _addConsoleMessage("✅ Commande PWM envoyée: $command", type: 'send');
      }
    } catch (e) {
      _addConsoleMessage("❌ Erreur envoi PWM: ${e.toString()}", type: 'error');
      if (!_isServerMode) {
        setState(() {
          _connectionStatus = ConnectionStatus.deconnected;
        });
      }
    }
  }

  Future<void> _checkAndRestoreConnection() async {
    if (_connectionStatus == ConnectionStatus.deconnected &&
        _persistenceConnexion.autoConnectEnabled) {
      _addConsoleMessage(
        "🔄 Vérification de la connexion au retour...",
        type: 'warning',
      );
      await _persistenceConnexion.attemptAutoReconnect();
    }
  }

  Future<void> _attemptAutoReconnectOnStartup() async {
    await Future.delayed(const Duration(seconds: 2));

    final success = await _persistenceConnexion.attemptAutoReconnect();
    if (success) {
      _addConsoleMessage(
        "✅ Reconnexion automatique au démarrage réussie",
        type: 'success',
      );

      setState(() {
        _connectionStatus = ConnectionStatus.connected;

        if (_persistenceConnexion.lastConnectionMode == 'wifi') {
          _connectionMode = ConnectionMode.wifi;
          _wifiProtocolMode =
              _persistenceConnexion.lastWifiProtocol ?? WiFiProtocol.http;

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

  // Méthodes de connexion Bluetooth
  Future<void> _connectToSelectedBluetoothDevice() async {
    if (_selectedBluetoothDevice == null) {
      Fluttertoast.showToast(msg: "Sélectionnez un appareil");
      return;
    }
    if (_isServerMode) {
      await _toggleServerMode(false);
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

  // Méthodes de connexion Wi-Fi
  Future<void> _connectToWifiDevice() async {
    final String ip = _ipController.text.trim();
    final int? port = int.tryParse(_portController.text.trim());

    if (ip.isEmpty || port == null) {
      Fluttertoast.showToast(msg: "IP/Port invalide");
      return;
    }

    if (_isServerMode) {
      await _toggleServerMode(false);
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

  Future<void> _disconnectDevice() async {
    if (_isServerMode) {
      setState(() {
        _serverConnected = false;
        _serverStatusMessage = 'Déconnecté';
      });
      _stopServerMessagesPolling();
      _addConsoleMessage("Déconnecté du serveur", type: 'info');
      return;
    }

    if (_connectionStatus == ConnectionStatus.deconnected) {
      _addConsoleMessage(
        "Aucun appareil n'est actuellement connecté.",
        type: 'info',
      );
      return;
    }

    _addConsoleMessage("Déconnexion de l'appareil...", type: 'info');
    try {
      _communicationService.disconnectAll();
      _addConsoleMessage("Déconnecté avec succès.", type: 'success');
      _persistenceConnexion.stopAutoReconnect();
      setState(() {
        _connectionStatus = ConnectionStatus.deconnected;
        _connectedDevice = '';
      });
    } catch (e) {
      _addConsoleMessage(
        "Erreur lors de la déconnexion: ${e.toString()}",
        type: 'error',
      );
    }
  }

  // Méthodes PWM
  void _updateChannelValue(int index, int value) {
    setState(() {
      _pwmChannels[index].currentValue = value;
    });
    _addConsoleMessage(
      'Valeur modifiée: ${_pwmChannels[index].name} -> $value',
      type: 'info',
    );
  }

  // MODIFIER _sendAllCommands pour vérifier la connexion serveur
  void _sendAllCommands() {
    if (_isServerMode) {
      if (!_serverConnected) {
        _addConsoleMessage(
          "❌ Impossible d'envoyer les commandes - Serveur non connecté",
          type: 'error',
        );
        Fluttertoast.showToast(msg: "Connectez-vous d'abord au serveur");
        return;
      }
    } else if (_connectionStatus != ConnectionStatus.connected) {
      _addConsoleMessage(
        "❌ Impossible d'envoyer les commandes - Non connecté",
        type: 'error',
      );
      Fluttertoast.showToast(msg: "Connectez-vous d'abord à un appareil");
      return;
    }

    _addConsoleMessage(
      '--- Envoi de toutes les commandes PWM ---',
      type: 'info',
    );

    for (var channel in _pwmChannels) {
      _sendPWMCommand(
        channel.pin,
        channel.currentValue,
        channel.frequency,
        channel.resolution,
        channel.sendFrequency,
        channel.sendResolution,
      );
    }

    _addConsoleMessage(
      '✅ Toutes les commandes PWM ont été envoyées',
      type: 'success',
    );
  }

  // MODIFIER _sendSingleCommand pour vérifier la connexion serveur
  void _sendSingleCommand(int index) {
    if (_isServerMode) {
      if (!_serverConnected) {
        _addConsoleMessage(
          "❌ Impossible d'envoyer la commande - Serveur non connecté",
          type: 'error',
        );
        Fluttertoast.showToast(msg: "Connectez-vous d'abord au serveur");
        return;
      }
    } else if (_connectionStatus != ConnectionStatus.connected) {
      _addConsoleMessage(
        "❌ Impossible d'envoyer la commande - Non connecté",
        type: 'error',
      );
      Fluttertoast.showToast(msg: "Connectez-vous d'abord à un appareil");
      return;
    }

    final channel = _pwmChannels[index];
    _sendPWMCommand(
      channel.pin,
      channel.currentValue,
      channel.frequency,
      channel.resolution,
      channel.sendFrequency,
      channel.sendResolution,
    );
  }

  // Gestion de la console
  void _addConsoleMessage(String message, {String type = 'info'}) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _consoleMessages.add(
        ConsoleMessage(text: message, timestamp: timestamp, type: type),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_consoleScrollController.hasClients) {
        _consoleScrollController.animateTo(
          _consoleScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearConsole() {
    setState(() {
      _consoleMessages.clear();
    });
  }

  void _toggleConsole() {
    setState(() {
      _showConsole = !_showConsole;
    });
  }

  void _selectChannel(int index) {
    if (!_editMode) return;
    setState(() {
      _selectedChannelIndex = index;
    });
  }

  // Dialogues de connexion
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
                            await _startBluetoothScan(setStateInDialog);
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
                                    setState(
                                      () => _selectedBluetoothDevice = value,
                                    );
                                    setStateInDialog(() {});
                                  },
                          );
                        },
                      ),
                    ),
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

  Future<void> _startBluetoothScan(StateSetter setStateInDialog) async {
    _addConsoleMessage("Démarrage du scan Bluetooth...");

    try {
      _communicationService.setActiveMode(CommunicationMode.bluetooth);
      _communicationService.bluetoothManager.setActiveProtocol(
        _bluetoothProtocolMode,
      );

      // CORRECTION ICI - Utilisez les nouvelles méthodes
      final bool isBluetoothOn = await _communicationService
          .isBluetoothEnabled();
      if (!isBluetoothOn) {
        _addConsoleMessage("Bluetooth désactivé. Tentative d'activation...");
        await _communicationService.setBluetoothEnabled(true);
        await Future.delayed(const Duration(seconds: 3));

        if (!await _communicationService.isBluetoothEnabled()) {
          _addConsoleMessage("Impossible d'activer le Bluetooth");
          setStateInDialog(() {
            _isScanningBluetooth = false;
          });
          return;
        }
      }

      // CORRECTION ICI - Utilisez la nouvelle méthode
      final foundDevices = await _communicationService.scanBluetoothDevices(
        protocol: _bluetoothProtocolMode,
        duration: 15,
      );

      setStateInDialog(() {
        _discoveredBluetoothDevices = foundDevices;
        _isScanningBluetooth = false;
      });

      if (foundDevices.isNotEmpty) {
        _addConsoleMessage(
          "${foundDevices.length} appareil(s) Bluetooth trouvé(s)",
        );
      } else {
        _addConsoleMessage("Aucun appareil Bluetooth trouvé");
      }
    } catch (e) {
      _addConsoleMessage("Erreur scan Bluetooth: ${e.toString()}");
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
              _deviceHistoryManager.clearDeviceHistory();
              Navigator.pop(context);
              Fluttertoast.showToast(msg: "Historique effacé");
            },
            child: const Text('Effacer l\'historique'),
          ),
        ],
      ),
    );
  }

  void _showPWMParametersModal() {
    showDialog(
      context: context,
      builder: (context) => PWMParametreModal(
        editMode: _editMode,
        onEditModeChanged: (value) {
          setState(() {
            _editMode = value;
          });
        },
        pwmChannels: _pwmChannels,
        onChannelUpdated: (index, updatedChannel) {
          setState(() {
            _pwmChannels[index] = updatedChannel;
          });
        },
        onAddChannel: _showAddChannelDialog,
        onDeleteChannel: (index) {
          setState(() {
            if (index >= 0 && index < _pwmChannels.length) {
              _addConsoleMessage(
                'Canal ${_pwmChannels[index].name} supprimé',
                type: 'warning',
              );
              _pwmChannels.removeAt(index);
            }
          });
        },
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
            .where((device) => device.mode == ConnectionMode.wifi)
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
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Aucun appareil Bluetooth récent'));
        }

        final bluetoothDevices = snapshot.data!
            .where((device) => device.mode == ConnectionMode.bluetooth)
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  // Construction de l'interface
  // Ajouter cette variable pour la position du bouton flottant
  Offset _fabOffset = Offset(0, 0);
  bool _isFabInitialized = false;

  // Modifier la méthode build pour le bouton flottant déplaçable
  @override
  @override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  // Initialiser la position du FAB au centre si ce n'est pas déjà fait
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_isFabInitialized && _fabOffset.dx == 0 && _fabOffset.dy == 0) {
      final size = MediaQuery.of(context).size;
      setState(() {
        _fabOffset = Offset(size.width / 2 - 30, size.height / 2 - 30);
        _isFabInitialized = true;
      });
    }
  });

  return Scaffold(
    appBar: AppBar(
      title: Text(
        ' PWM-Contrôle-ESP32',
        style: GoogleFonts.interTight(
          fontWeight: FontWeight.w600,
          color: colorScheme.onPrimary,
        ),
      ),
      backgroundColor: colorScheme.primary,
      centerTitle: true,
      actions: [
        // Historique des appareils
        IconButton(
          icon: const Icon(Icons.history),
          onPressed: _showDeviceHistoryDialog,
          tooltip: 'Historique des appareils',
        ),

        // Icône de connexion unifiée
        IconButton(
          icon: Icon(
            _getConnectionIcon(),
            color: _getConnectionColor(),
          ),
          onPressed: _showConnectionTypeModal,
          tooltip: 'Choisir le type de connexion',
        ),

        // Icône serveur unique (remplace les deux précédentes)
        _buildServerStatusIcon(),

        // Configuration des canaux PWM
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: _showPWMParametersModal,
          tooltip: 'Configurer les canaux',
        ),
      ],
    ),
    body: Stack(
      children: [
        Column(
          children: [
            // Barre d'état de connexion - MODIFIÉE pour gérer le débordement
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 16,
              ),
              color: _getConnectionStatusColor().withOpacity(0.2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 12,
                              color: _getConnectionStatusColor(),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _getConnectionStatusText(),
                                style: TextStyle(
                                  color: _getConnectionStatusColor(),
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if ((_connectionStatus == ConnectionStatus.connected &&
                              !_isServerMode) ||
                          (_isServerMode && _serverConnected))
                        IconButton(
                          icon: const Icon(
                            Icons.link_off,
                            color: Colors.red,
                            size: 20,
                          ),
                          onPressed: _disconnectDevice,
                          tooltip: 'Déconnecter',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                    ],
                  ),
                  if ((_connectionStatus == ConnectionStatus.connected &&
                          !_isServerMode) ||
                      (_isServerMode && _serverConnected))
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: 2),
                      child: Text(
                        _isServerMode
                            ? "Serveur: ${ServerBack.activeBaseUrl}"
                            : _connectedDevice,
                        style: TextStyle(
                          color: _getConnectionStatusColor(),
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                ],
              ),
            ),

            // Contenu principal
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Liste des canaux PWM
                    Expanded(
                      child: ListView.builder(
                        itemCount: _pwmChannels.length,
                        itemBuilder: (context, index) =>
                            _buildPWMChannelCard(index),
                      ),
                    ),

                    // Bouton pour ajouter des canaux (en mode édition)
                    if (_editMode) _buildAddChannelButton(),
                  ],
                ),
              ),
            ),

            // Console - TOUJOURS visible en bas, mais réduite/masquée
            _buildConsole(),
          ],
        ),

        // Bouton flottant déplaçable pour envoyer toutes les commandes
        if (_isFabInitialized)
          Positioned(
            left: _fabOffset.dx,
            top: _fabOffset.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _fabOffset = Offset(
                    _fabOffset.dx + details.delta.dx,
                    _fabOffset.dy + details.delta.dy,
                  );
                });
              },
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _connectionStatus == ConnectionStatus.connected
                      ? colorScheme.primary
                      : Colors.grey,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _connectionStatus == ConnectionStatus.connected
                      ? _sendAllCommands
                      : null,
                  icon: const Icon(Icons.send, color: Colors.white, size: 24),
                  tooltip: 'Envoyer toutes les commandes PWM',
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

 Widget _buildServerStatusIcon() {
  return Stack(
    children: [
      IconButton(
        icon: Icon(
          Icons.cloud_done,
          color: _isServerMode
              ? (_serverConnected ? Colors.indigoAccent : Colors.orange)
              : Colors.white,
        ),
        onPressed: _showServerConfigModal,
        tooltip: _buildServerTooltip(),
      ),
      if (_isServerMode && !_serverConnected)
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                '!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

// NOUVELLE MÉTHODE : Tooltip dynamique pour le serveur
String _buildServerTooltip() {
  if (_isServerMode) {
    if (_serverConnected) {
      return 'Serveur connecté - ${ServerBack.activeBaseUrl}\nCliquer pour configurer';
    } else {
      return 'Serveur déconnecté\nCliquer pour configurer';
    }
  } else {
    return 'Configurer le mode serveur';
  }
}

  Color _getConnectionColor() {
    if (_isServerMode) {
      return _serverConnected ? Colors.green : Colors.orange;
    }
    return _connectionStatus == ConnectionStatus.connected
        ? Colors.white
        : Colors.white.withAlpha((0.7 * 255).toInt());
  }

  Widget _buildPWMChannelCard(int index) {
    final channel = _pwmChannels[index];
    final theme = Theme.of(context);
    final isSelected = _selectedChannelIndex == index;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: isSelected
          ? theme.colorScheme.primary.withOpacity(0.1)
          : theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? theme.colorScheme.primary : theme.dividerColor,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _editMode ? () => _selectChannel(index) : null,
        onLongPress: () => _selectChannel(index),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(channel.icon, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        channel.name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'GPIO ${channel.pin} | ${channel.currentValue}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: channel.currentValue.toDouble(),
                      min: channel.minValue.toDouble(),
                      max: channel.maxValue.toDouble(),
                      divisions: channel.maxValue - channel.minValue,
                      label: channel.currentValue.toString(),
                      onChanged: (value) =>
                          _updateChannelValue(index, value.toInt()),
                      activeColor: theme.colorScheme.primary,
                      inactiveColor: theme.colorScheme.surfaceVariant,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => _sendSingleCommand(index),
                    tooltip: 'Envoyer la commande PWM',
                  ),
                ],
              ),
              if (_editMode && isSelected) ...[
                const Divider(),
                _buildChannelConfigInfo(channel),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelConfigInfo(PWMChannel channel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configuration:',
          style: GoogleFonts.inter(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Fréquence: ${channel.frequency} Hz'),
            Text('Résolution: ${channel.resolution} bits'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildConfigToggle('Fréquence', channel.sendFrequency, (value) {
              setState(() {
                channel.sendFrequency = value;
              });
            }),
            const SizedBox(width: 16),
            _buildConfigToggle('Résolution', channel.sendResolution, (value) {
              setState(() {
                channel.sendResolution = value;
              });
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildConfigToggle(
    String label,
    bool value,
    Function(bool) onChanged,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Envoyer $label:'),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildConsole() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.95),
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // En-tête de la console (TOUJOURS visible)
          GestureDetector(
            onTap: _toggleConsole,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                border: Border(
                  bottom: _showConsole
                      ? BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        )
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.terminal,
                    color: Theme.of(context).colorScheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Console de débogage',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 14,
                      ),
                    ),
                  ),

                  // Indicateur de statut compact
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getConnectionStatusColor().withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: _getConnectionStatusColor(),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _getConnectionStatusText(),
                          style: TextStyle(
                            fontSize: 11,
                            color: _getConnectionStatusColor(),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Badge du nombre de messages
                  if (_consoleMessages.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_consoleMessages.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),

                  IconButton(
                    icon: Icon(
                      Icons.clear_all,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.7),
                      size: 18,
                    ),
                    onPressed: _clearConsole,
                    tooltip: 'Effacer la console',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),

                  IconButton(
                    icon: Icon(
                      _showConsole
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    onPressed: _toggleConsole,
                    tooltip: _showConsole
                        ? 'Réduire la console'
                        : 'Développer la console',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Contenu de la console (conditionnel)
          if (_showConsole) ...[
            Container(
              constraints: const BoxConstraints(minHeight: 120, maxHeight: 300),
              child: Column(
                children: [
                  // Filtres et contrôles
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _buildConsoleFilterChip('Tous', 'all'),
                            _buildConsoleFilterChip('Infos', 'info'),
                            _buildConsoleFilterChip('Succès', 'success'),
                            _buildConsoleFilterChip('Erreurs', 'error'),
                            _buildConsoleFilterChip('Envoi', 'send'),
                            _buildConsoleFilterChip('Reçu', 'receive'),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          '${_filteredConsoleMessages.length} messages',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Liste des messages
                  Expanded(
                    child: Container(
                      color: Theme.of(context).colorScheme.background,
                      child: Scrollbar(
                        controller: _consoleScrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _consoleScrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: _filteredConsoleMessages.length,
                          itemBuilder: (context, index) {
                            return _buildConsoleMessageItem(
                              _filteredConsoleMessages[index],
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  // Champ de commande manuelle
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualCommandController,
                            decoration: InputDecoration(
                              hintText: 'Entrez une commande manuelle...',
                              filled: true,
                              fillColor: Theme.of(
                                context,
                              ).colorScheme.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.history, size: 18),
                                onPressed: _showCommandHistory,
                                tooltip: 'Historique des commandes',
                              ),
                            ),
                            onSubmitted: (value) => _sendManualCommand(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.send, size: 16),
                          label: const Text('Envoyer'),
                          onPressed: _sendManualCommand,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConsoleMessageItem(ConsoleMessage message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: message.color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: message.color, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: message.color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(message.icon, size: 12, color: message.color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        message.type.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: message.color,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      message.timestamp,
                      style: TextStyle(
                        fontSize: 9,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.5),
                        fontFamily: 'RobotoMono',
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        Icons.content_copy,
                        size: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.4),
                      ),
                      onPressed: () => _copyMessageToClipboard(message.text),
                      tooltip: 'Copier le message',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontFamily: 'RobotoMono',
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _consoleFilter = 'all';

  Widget _buildConsoleFilterChip(String label, String value) {
    final bool isSelected = _consoleFilter == value;

    // Labels abrégés pour économiser de l'espace
    final Map<String, String> abbreviatedLabels = {
      'all': 'Tous',
      'info': 'Info',
      'success': 'Succès',
      'error': 'Erreur',
      'send': 'Envoi',
      'receive': 'Reçu',
    };

    final String displayLabel = abbreviatedLabels[value] ?? label;

    return Tooltip(
      message: label,
      child: Container(
        margin: const EdgeInsets.only(right: 4, bottom: 4),
        child: GestureDetector(
          onTap: () {
            setState(() {
              _consoleFilter = isSelected ? 'all' : value;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            constraints: const BoxConstraints(minWidth: 35, maxWidth: 50),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
            child: Text(
              displayLabel,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddChannelButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(top: 16),
      child: _editMode
          ? ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un canal PWM'),
              onPressed: _showAddChannelDialog,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )
          : const SizedBox.shrink(), // Cache le bouton quand pas en mode édition
    );
  }

  // Méthode pour obtenir l'icône de connexion appropriée
  IconData _getConnectionIcon() {
    if (_isServerMode) {
      return _serverConnected ? Icons.link_off : Icons.cloud_off;
    } else if (_connectionStatus == ConnectionStatus.connected) {
      switch (_connectionMode) {
        case ConnectionMode.bluetooth:
          return Icons.bluetooth_connected;
        case ConnectionMode.wifi:
          return Icons.wifi_rounded;
        case ConnectionMode.none:
          return Icons.link_off;
      }
    } else {
      return Icons.link;
    }
  }

  // MODIFIER _showConnectionTypeModal pour inclure le serveur
  void _showConnectionTypeModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Type de connexion',
              style: GoogleFonts.roboto(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Option Bluetooth
            ListTile(
              leading: Icon(
                Icons.bluetooth,
                color:
                    !_isServerMode &&
                        _connectionMode == ConnectionMode.bluetooth
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              title: Text('Bluetooth'),
              subtitle: Text('Connecter via Bluetooth'),
              trailing:
                  !_isServerMode && _connectionMode == ConnectionMode.bluetooth
                  ? Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.pop(context);
                _showBluetoothConnectionDialog(context);
              },
            ),

            // Option Wi-Fi
            ListTile(
              leading: Icon(
                Icons.wifi,
                color: !_isServerMode && _connectionMode == ConnectionMode.wifi
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              title: Text('Wi-Fi'),
              subtitle: Text('Connecter via réseau Wi-Fi'),
              trailing: !_isServerMode && _connectionMode == ConnectionMode.wifi
                  ? Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.pop(context);
                _showWifiConnectionDialog(context);
              },
            ),

            // Option Serveur
            ListTile(
              leading: Icon(
                Icons.cloud,
                color: _isServerMode
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              title: Text('Serveur'),
              subtitle: Text('Connecter via serveur cloud'),
              trailing: _isServerMode
                  ? Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.pop(context);
                _showServerConfigModal();
              },
            ),

            // Option Déconnexion si connecté
            if ((_connectionStatus == ConnectionStatus.connected &&
                    !_isServerMode) ||
                (_isServerMode && _serverConnected))
              ListTile(
                leading: Icon(Icons.link_off, color: Colors.red),
                title: Text('Déconnecter', style: TextStyle(color: Colors.red)),
                subtitle: Text('Se déconnecter'),
                onTap: () {
                  Navigator.pop(context);
                  _disconnectDevice();
                },
              ),
          ],
        ),
      ),
    );
  }

  // Méthode pour les paramètres du serveur (à implémenter)
  void _showServerSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Paramètres du serveur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.info),
              title: Text('Statut du serveur'),
              subtitle: Text(
                _connectionStatus == ConnectionStatus.connected
                    ? 'Connecté à $_connectedDevice'
                    : 'Non connecté',
              ),
            ),
            ListTile(
              leading: Icon(Icons.autorenew),
              title: Text('Reconnexion automatique'),
              subtitle: Text(
                _persistenceConnexion.autoConnectEnabled
                    ? 'Activée'
                    : 'Désactivée',
              ),
              trailing: Switch(
                value: _persistenceConnexion.autoConnectEnabled,
                onChanged: (value) {
                  setState(() {
                    _persistenceConnexion.autoConnectEnabled;
                  });
                  Navigator.pop(context);
                  Fluttertoast.showToast(
                    msg: value
                       
                        ? 'Connexion automatique'
                        : 'Connexion automatique',
                  );
                },
              ),
            ),
            ListTile(
              leading: Icon(Icons.speed),
              title: Text('Console de débogage'),
              subtitle: Text(_showConsole ? 'Visible' : 'Cachée'),
              trailing: Switch(
                value: _showConsole,
                onChanged: (value) {
                  setState(() {
                    _showConsole = value;
                  });
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _showAddChannelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter un canal PWM'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Nom du canal'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Numéro GPIO'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Fréquence (Hz)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Résolution (bits)',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              // Logique pour ajouter un nouveau canal
              final newChannel = PWMChannel(
                id: _pwmChannels.length + 1,
                name: 'Nouveau Canal',
                icon: Icons.settings,
                minValue: 0,
                maxValue: 255,
                currentValue: 0,
                pin: 0,
                frequency: 1000,
                resolution: 8,
                sendFrequency: false,
                sendResolution: false,
              );

              setState(() {
                _pwmChannels.add(newChannel);
              });

              _addConsoleMessage(
                'Nouveau canal PWM ajouté: ${newChannel.name}',
              );
              Navigator.pop(context);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  // Méthodes utilitaires
  Color _getConnectionStatusColor() {
    if (_isServerMode) {
      return _serverConnected ? Colors.green : Colors.red;
    }
    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.connecting:
        return Colors.orange;
      case ConnectionStatus.deconnected:
        return Colors.red;
    }
  }

  String _getConnectionStatusText() {
    if (_isServerMode) {
      return _serverConnected ? 'Connecté au' : 'Serveur déconnecté';
    }
    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        return 'Connecté';
      case ConnectionStatus.connecting:
        return 'Connexion en cours...';
      case ConnectionStatus.deconnected:
        return 'Déconnecté';
    }
  }
}

// Classe représentant un canal PWM
class PWMChannel {
  final int id;
  String name;
  final IconData icon;
  int minValue;
  int maxValue;
  int currentValue;
  int pin;
  int frequency; // en Hz
  int resolution; // en bits
  bool sendFrequency; // Activer l'envoi de la fréquence
  bool sendResolution; // Activer l'envoi de la résolution

  PWMChannel({
    required this.id,
    required this.name,
    required this.icon,
    required this.minValue,
    required this.maxValue,
    required this.currentValue,
    required this.pin,
    required this.frequency,
    required this.resolution,
    this.sendFrequency = false,
    this.sendResolution = false,
  });
}
