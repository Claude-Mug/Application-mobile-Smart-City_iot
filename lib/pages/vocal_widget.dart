// vocal_widget.dart - VERSION AMÉLIORÉE AVEC PERSISTANCE COMPLÈTE
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:claude_iot/services/services.commun.dart' hide CommunicationMode;
import 'package:claude_iot/services/services.bluetooth.dart';
import 'package:claude_iot/utils/persistence_connexion.dart';
import 'package:claude_iot/commande/command_settings.dart';
import 'package:claude_iot/server/server_back.dart';
import 'package:claude_iot/server/server_front.dart';

void main() {
  runApp(const VocalApp());
}

class VocalApp extends StatelessWidget {
  const VocalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vocale IoT Commande',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: GoogleFonts.interTextTheme(),
        useMaterial3: true,
      ),
      home: const VocalScreen(),
    );
  }
}

// Classes pour l'historique des appareils (copiées de terminal_widget.dart)
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
      protocol: map['protocol'] != null ? 
          (map['mode'] == ConnectionMode.bluetooth.index ? 
           BluetoothProtocol.values[map['protocol']] : 
           WiFiProtocol.values[map['protocol']]) : null,
    );
  }
}

class DeviceHistoryManager {
  static const String _storageKey = 'vocal_device_history';
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
    
    final List<DeviceHistory> limitedHistory = history.take(_maxDevices).toList();
    
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

class VocalScreen extends StatefulWidget {
  const VocalScreen({super.key});

  @override
  State<VocalScreen> createState() => _VocalScreenState();
}

class _VocalScreenState extends State<VocalScreen> with WidgetsBindingObserver {
  final SpeechToText _speechToText = SpeechToText();
  final CommunicationService _comService = CommunicationService();
  late PersistenceConnexion _persistenceConnexion;
  final DeviceHistoryManager _deviceHistoryManager = DeviceHistoryManager();

  // Nouvelles variables pour les paramètres des commandes
  late CommandSettings _commandSettings;
  final CommandSettingsManager _commandSettingsManager = CommandSettingsManager();
  final TextEditingController _prefixController = TextEditingController();
  
  bool _isRecording = false;
  bool _isConnected = false;
  ConnectionMode _connectionMode = ConnectionMode.none;
  final List<VoiceCommand> _commandHistory = [];
  bool _micEnabled = true;
  String _currentCommandText = "";
  String? _wifiIp;
  int _wifiPort = 81;
  BluetoothDevice? _selectedBluetoothDevice;
  String _connectionStatus = "Non connecté";

  // Variable config Server
  bool _isServerMode = false;
  bool _serverConnected = false;
  String _serverStatusMessage = 'Non connecté au serveur';
  Timer? _serverMessagesTimer;
  List<dynamic> _serverMessages = [];

  bool get _displayConnected {
  if (_isServerMode) {
    return _serverConnected;
  } else {
    return _isConnected;
  }
}
  
  // États pour la configuration
  BluetoothProtocol _bluetoothProtocol = BluetoothProtocol.classic;
  WiFiProtocol _wifiProtocol = WiFiProtocol.http;


  // Contrôleurs pour les champs Wi-Fi
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '81');

  @override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  _initServices();
  _initSpeechToText();
  _initializePersistenceConnexion();
  _loadCommandSettings(); // Charger les paramètres
  _loadServerSettings();

  // Restaurer la connexion après l'initialisation
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _attemptAutoReconnectOnStartup();
  });
}

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistenceConnexion.dispose();
    _comService.dispose();
    _ipController.dispose();
    _portController.dispose();
    _serverMessagesTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRestoreConnection();
    }
  }

  // Charger les paramètres serveur
Future<void> _loadServerSettings() async {
  final prefs = await SharedPreferences.getInstance();
  setState(() {
    _isServerMode = prefs.getBool('server_mode') ?? false;
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
      _addCommandToHistory("✅ Connecté au serveur: ${ServerBack.activeBaseUrl}", true, true);
      _startServerMessagesPolling();
      _fetchServerMessages();
    } else {
      _addCommandToHistory("❌ Erreur serveur: ${result['message']}", false, true);
      _stopServerMessagesPolling();
    }
    _updateConnectionStatus();
  });
}

// Basculer entre mode serveur et mode local
 Future<void>  _toggleServerMode(bool value) async {
  // Mettre à jour l'état immédiatement pour une meilleure réactivité
  setState(() {
    _isServerMode = value;
  });

  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('server_mode', value);

  if (!value) {
    setState(() {
      _serverConnected = false;
      _serverStatusMessage = 'Mode local activé';
    });
    _stopServerMessagesPolling();
    // Mettre à jour le statut de connexion
    _updateConnectionStatus();
  } else {
    // Tester la connexion immédiatement
    _testServerConnection();
  }
  _updateConnectionStatus();
  // Ajouter un message à l'historique
  _addCommandToHistory(
    value ? "🔄 Activation du mode serveur..." : "🔄 Désactivation du mode serveur", 
    true, 
    true
  );
}
// Démarrer la récupération des messages serveur
void _startServerMessagesPolling() {
  _serverMessagesTimer?.cancel();
  _serverMessagesTimer = Timer.periodic(Duration(seconds: 3), (timer) {
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
        if (!_commandHistory.any((cmd) => cmd.text.contains(formattedMessage))) {
          _addCommandToHistory("Serveur: $formattedMessage", true, true, isResponse: true);
        }
      }
      
      _serverMessages = newMessages;
    } else {
      final errorMsg = result['message'] ?? 'Unknown error';
      _addCommandToHistory("Erreur récupération messages: $errorMsg", false, true);
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

// Formater la date
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

  Future<void> _checkAndRestoreConnection() async {
    if (!_isConnected && _persistenceConnexion.autoConnectEnabled) {
      _addCommandToHistory("🔄 Vérification de la connexion au retour...", true, true);
      await _persistenceConnexion.attemptAutoReconnect();
    }
  }

  Future<void> _loadCommandSettings() async {
  final settings = await _commandSettingsManager.getSettings();
  setState(() {
    _commandSettings = settings;
    _prefixController.text = _commandSettings.customPrefix;
  });
}

  void _initializePersistenceConnexion() {
    _persistenceConnexion = PersistenceConnexion(
      onLogMessage: (message) {
        _addCommandToHistory(message, true, true);
      },
      onConnectionStatusChanged: (connected) {
        setState(() {
          _isConnected = connected;
          _updateConnectionStatus();
        });
      },
      onReconnectStarted: () {
        _addCommandToHistory("🔄 Reconnexion automatique en cours...", true, true);
      },
      onReconnectSuccess: (ip, port, microcontrollerType) {
        _addCommandToHistory("✅ Reconnexion Wi-Fi réussie à $ip:$port", true, true);
        setState(() {
          _isConnected = true;
          _connectionMode = ConnectionMode.wifi;
          _wifiIp = ip;
          _wifiPort = port;
          _updateConnectionStatus();
        });
      },
      onBluetoothReconnectSuccess: (device) {
        _addCommandToHistory("✅ Reconnexion Bluetooth réussie à ${device.name}", true, true);
        setState(() {
          _isConnected = true;
          _connectionMode = ConnectionMode.bluetooth;
          _selectedBluetoothDevice = device;
          _updateConnectionStatus();
        });
      },
      onReconnectFailed: (error) {
        _addCommandToHistory("❌ Échec reconnexion: $error", false, true);
      },
      communicationService: _comService,
    );
    
    _persistenceConnexion.initialize();
  }

  Future<void> _attemptAutoReconnectOnStartup() async {
    await Future.delayed(const Duration(seconds: 2));
    
    final success = await _persistenceConnexion.attemptAutoReconnect();
    if (success) {
      _addCommandToHistory("✅ Reconnexion automatique au démarrage réussie", true, true);
      
      setState(() {
        _isConnected = true;
        
        // Mettre à jour l'interface selon le mode avec les valeurs persistantes
        if (_persistenceConnexion.lastConnectionMode == 'wifi') {
          _connectionMode = ConnectionMode.wifi;
          _wifiProtocol = _persistenceConnexion.lastWifiProtocol ?? WiFiProtocol.http;
          _wifiIp = _persistenceConnexion.lastConnectedIP;
          _wifiPort = _persistenceConnexion.lastConnectedPort ?? 81;
          _updateConnectionStatus();
        } else if (_persistenceConnexion.lastConnectionMode == 'bluetooth') {
          _connectionMode = ConnectionMode.bluetooth;
          _bluetoothProtocol = _persistenceConnexion.lastBluetoothProtocol ?? BluetoothProtocol.classic;
          if (_persistenceConnexion.lastBluetoothDeviceId != null) {
            _selectedBluetoothDevice = BluetoothDevice(
              id: _persistenceConnexion.lastBluetoothDeviceId!,
              name: _persistenceConnexion.lastBluetoothDeviceName ?? 'Appareil Bluetooth',
              isBle: _persistenceConnexion.lastBluetoothProtocol == BluetoothProtocol.ble,
            );
          }
          _updateConnectionStatus();
        }
      });
    }
  }

  void _updateConnectionStatus() {
  if (_isServerMode) {
    _connectionStatus = _serverConnected 
      ? "Connecté au serveur: ${ServerBack.activeBaseUrl}"
      : "Serveur non connecté";
  } else if (_isConnected) {
    if (_connectionMode == ConnectionMode.bluetooth && _selectedBluetoothDevice != null) {
      _connectionStatus = "Connecté via Bluetooth (${_bluetoothProtocol.name}) à ${_selectedBluetoothDevice!.name}";
    } else if (_connectionMode == ConnectionMode.wifi && _wifiIp != null) {
      _connectionStatus = "Connecté via Wi-Fi (${_wifiProtocol.name}) à $_wifiIp:$_wifiPort";
    } else {
      _connectionStatus = "Connecté";
    }
  } else {
    _connectionStatus = "Non connecté";
  }
}

   // Méthode pour afficher la configuration détaillée du serveur
  void _showServerConfigModal() {
  showDialog(
    context: context,
    barrierDismissible: true, // Permet de fermer en cliquant à l'extérieur
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        width: MediaQuery.of(context).size.width * 0.75,
        decoration: BoxDecoration(
          color: Colors.white, // Fond blanc pour meilleur contraste
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

  Future<void> _initServices() async {
    _comService.initialize();
    
    // Écouter les changements d'état de connexion
    _comService.globalConnectionStateStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          _isConnected = isConnected;
          _updateConnectionStatus();
        });
      }
    });

    // Écouter les données reçues
    _comService.globalReceivedDataStream.listen((data) {
      if (mounted) {
        _addCommandToHistory("Réponse: $data", true, true, isResponse: true);
      }
    });
  }

  Future<void> _initSpeechToText() async {
    _micEnabled = await _speechToText.initialize();
    if (mounted) setState(() {});
  }

  void _addCommandToHistory(String text, bool success, bool isSystem, {bool isResponse = false}) {
    setState(() {
      _commandHistory.insert(0, VoiceCommand(
        text: text,
        mode: _connectionMode,
        time: DateTime.now(),
        success: success,
        isResponse: isResponse,
        isSystem: isSystem,
      ));
    });
  }

  void _startListening() async {
  if (!_isServerMode && _connectionMode == ConnectionMode.none) {
    _showConnectionModeDialog();
    return;
  }

  if (!_isServerMode && !_isConnected) {
    _addCommandToHistory("❌ Aucun appareil connecté", false, true);
    return;
  }

  if (_isServerMode && !_serverConnected) {
    _addCommandToHistory("❌ Serveur non connecté", false, true);
    return;
  }

  if (_micEnabled && !_speechToText.isListening) {
    setState(() {
      _isRecording = true;
      _currentCommandText = "J'écoute...";
    });
    await _speechToText.listen(
      onResult: (result) {
        final normalized = normalizeCommand(result.recognizedWords);
        setState(() {
          _currentCommandText = normalized;
        });
        if (result.finalResult) {
          _stopListeningAndProcessCommand(normalized);
        }
      },
    );
  }
}

  void _stopListeningAndProcessCommand(String normalizedCommand) async {
    await _speechToText.stop();
    setState(() {
      _isRecording = false;
      if (normalizedCommand.isNotEmpty) {
        _addCommandToHistory(normalizedCommand, true, false);
        _sendCommand(normalizedCommand);
      }
    });
  }

 String normalizeCommand(String command) {
  return normalizeCommandWithSettings(command, _commandSettings);
}

  void _sendCommand(String normalizedCommand) async {
  try {
    if (_isServerMode) {
      // Envoi via le serveur
      if (!_serverConnected) {
        _addCommandToHistory("❌ Serveur non connecté", false, true);
        return;
      }
      
      final result = await ServerBack.sendCommand(normalizedCommand);
      
      setState(() {
        if (result['success'] == true) {
          _addCommandToHistory("Commande envoyée au serveur: '$normalizedCommand'", true, true);
          _addCommandToHistory("Réponse serveur: ${result['message']}", true, true, isResponse: true);
        } else {
          _addCommandToHistory("Erreur serveur: ${result['message']}", false, true);
        }
      });
    } else {
      // Envoi local (code existant)
      if (_connectionMode == ConnectionMode.bluetooth && _selectedBluetoothDevice != null) {
        await _comService.sendBluetoothCommand(normalizedCommand);
        _addCommandToHistory("Commande Bluetooth envoyée: '$normalizedCommand'", true, true);
      } else if (_connectionMode == ConnectionMode.wifi && _wifiIp != null) {
        if (_wifiProtocol == WiFiProtocol.websocket) {
          _comService.sendWebSocketMessage(normalizedCommand);
          _addCommandToHistory("Message WebSocket envoyé: '$normalizedCommand'", true, true);
        } else {
          final result = await _comService.sendHttpCommand(
            ip: _wifiIp!,
            port: _wifiPort,
            command: normalizedCommand,
          );
          _addCommandToHistory(
            result.success ? "HTTP Réussi: ${result.message}" : "HTTP Erreur: ${result.message}",
            result.success,
            true,
            isResponse: true
          );
        }
      }
    }
  } catch (e) {
    _addCommandToHistory("Erreur lors de l'envoi: ${e.toString()}", false, true);
  }
}

  void _toggleRecording() {
    if (!_micEnabled) return;
    if (_speechToText.isListening) {
      _stopListeningAndProcessCommand(_currentCommandText);
    } else {
      _startListening();
    }
  }

  // Méthodes de connexion avec persistance
  Future<void> _connectToWifiDevice() async {
    final String ip = _ipController.text.trim();
    final int? port = int.tryParse(_portController.text.trim());

    if (ip.isEmpty || port == null) {
      Fluttertoast.showToast(msg: "IP/Port invalide");
      return;
    }

    setState(() {
      _connectionStatus = "Connexion en cours...";
    });

    final success = await _persistenceConnexion.connectWifi(ip, port, _wifiProtocol);
    
    if (success) {
      // Ajouter à l'historique
      final deviceHistory = DeviceHistory(
        id: '$ip:$port',
        name: 'Appareil Wi-Fi',
        address: '$ip:$port',
        mode: ConnectionMode.wifi,
        lastConnected: DateTime.now(),
        protocol: _wifiProtocol,
      );
      await _deviceHistoryManager.addDeviceToHistory(deviceHistory);

      setState(() {
        _isConnected = true;
        _connectionMode = ConnectionMode.wifi;
        _wifiIp = ip;
        _wifiPort = port;
        _updateConnectionStatus();
      });
      Fluttertoast.showToast(msg: "Connecté avec succès!");
    } else {
      setState(() {
        _isConnected = false;
        _updateConnectionStatus();
      });
      Fluttertoast.showToast(msg: "Échec de connexion");
    }
  }

  Future<void> _connectToSelectedBluetoothDevice(BluetoothDevice device, BluetoothProtocol protocol) async {
    setState(() {
      _connectionStatus = "Connexion en cours...";
    });

    final success = await _persistenceConnexion.connectBluetooth(device, protocol);

    if (success) {
      // Ajouter à l'historique
      final deviceHistory = DeviceHistory(
        id: device.id,
        name: device.name,
        address: device.id,
        mode: ConnectionMode.bluetooth,
        lastConnected: DateTime.now(),
        protocol: protocol,
      );
      await _deviceHistoryManager.addDeviceToHistory(deviceHistory);

      setState(() {
        _isConnected = true;
        _connectionMode = ConnectionMode.bluetooth;
        _selectedBluetoothDevice = device;
        _bluetoothProtocol = protocol;
        _updateConnectionStatus();
      });
      Fluttertoast.showToast(msg: "Connecté à ${device.name} !");
    } else {
      setState(() {
        _isConnected = false;
        _updateConnectionStatus();
      });
      Fluttertoast.showToast(msg: "Échec de connexion Bluetooth");
    }
  }

  void _disconnect() async {
  if (_isServerMode) {
    setState(() {
      _serverConnected = false;
      _serverStatusMessage = 'Déconnecté';
    });
    _stopServerMessagesPolling();
    _addCommandToHistory("Déconnecté du serveur", true, true);
    return;
  }
  
  if (!_isConnected) {
    _addCommandToHistory("Aucun appareil connecté", true, true);
    return;
  }
  
  _addCommandToHistory("Déconnexion de l'appareil...", true, true);
  try {
    _comService.disconnectAll();
    _persistenceConnexion.stopAutoReconnect();
    _addCommandToHistory("Déconnecté avec succès", true, true);
    
    setState(() {
      _isConnected = false;
      _updateConnectionStatus();
    });
  } catch (e) {
    _addCommandToHistory("Erreur lors de la déconnexion: ${e.toString()}", false, true);
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

  Widget _buildPersistenceTab() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paramètres de Persistance',
          style: GoogleFonts.inter(
            color: Colors.black, // Texte noir
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        
        // Carte de statut
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100], // Fond gris clair
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _isConnected ? Icons.check_circle : Icons.error,
                    color: _isConnected ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Statut de la connexion',
                    style: GoogleFonts.inter(
                      color: Colors.black, // Texte noir
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isConnected ? 'Connecté' : 'Déconnecté',
                style: GoogleFonts.inter(
                  color: _isConnected ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Reconnexion automatique
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
                    Icon(Icons.autorenew, color: Colors.grey[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reconnexion automatique',
                            style: GoogleFonts.inter(color: Colors.black),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          Text(
                            _persistenceConnexion.autoConnectEnabled ? 'Activée' : 'Désactivée',
                            style: GoogleFonts.inter(
                              color: _persistenceConnexion.autoConnectEnabled 
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
              Switch(
                value: _persistenceConnexion.autoConnectEnabled,
                onChanged: (value) {
                  _persistenceConnexion.setAutoReconnect(value);
                  setState(() {});
                  Fluttertoast.showToast(
                    msg: "Reconnexion auto ${value ? 'activée' : 'désactivée'}"
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Historique des appareils
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history, color: Colors.grey[700]),
                  const SizedBox(width: 12),
                  Text(
                    'Historique des appareils',
                    style: GoogleFonts.inter(color: Colors.black),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: ElevatedButton(
                      onPressed: _showDeviceHistoryDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Voir l\'historique',
                        style: GoogleFonts.inter(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: OutlinedButton(
                      onPressed: () {
                        _persistenceConnexion.clearConnectionHistory();
                        _clearDeviceHistory();
                        Fluttertoast.showToast(msg: "Historique effacé");
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Effacer',
                        style: GoogleFonts.inter(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Informations détaillées
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blueGrey[900],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.lightBlueAccent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Informations détaillées',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              
              Builder(
                builder: (context) {
                  final status = _persistenceConnexion.getConnectionStatus();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Mode :', status['lastConnectionMode']?.toString() ?? 'Aucun'),
                      _buildInfoRow('Reconnexion auto :', (status['autoConnectEnabled'] ?? false) ? 'ON' : 'OFF'),
                      _buildInfoRow('Tentatives :', '${status['reconnectAttempts'] ?? 0}/${status['maxReconnectAttempts'] ?? 0}'),
                      
                      if (status['wifiSettings'] != null && status['wifiSettings']['ip'] != null)
                        _buildInfoRow('Wi-Fi :', '${status['wifiSettings']['ip']}:${status['wifiSettings']['port']}'),
                      
                      if (status['bluetoothSettings'] != null && status['bluetoothSettings']['deviceName'] != null)
                        _buildInfoRow('Bluetooth', status['bluetoothSettings']['deviceName'].toString()),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildInfoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.blue,
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// Mettre à jour _buildCommandTab pour le thème clair
Widget _buildCommandTab() {
  return StatefulBuilder(
    builder: (context, setState) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paramètres des Commandes',
              style: GoogleFonts.inter(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Transformation du texte
            _buildSectionTitle('Transformation du texte'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTransformChip('Minuscule', TextTransform.lowercase, setState),
                _buildTransformChip('Majuscule', TextTransform.uppercase, setState),
                _buildTransformChip('Capitaliser', TextTransform.capitalize, setState),
                _buildTransformChip('Normal', TextTransform.normal, setState),
              ],
            ),
            const SizedBox(height: 20),

            // Gestion des espaces
            _buildSectionTitle('Gestion des espaces'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildSpaceChip('Tiret bas (_)', SpaceReplacement.underscore, setState),
                _buildSpaceChip('Tiret (-)', SpaceReplacement.dash, setState),
                _buildSpaceChip('Aucun', SpaceReplacement.none, setState),
                _buildSpaceChip('Espace', SpaceReplacement.space, setState),
              ],
            ),
            const SizedBox(height: 20),

            // Options supplémentaires
            _buildSectionTitle('Options supplémentaires'),
            const SizedBox(height: 8),
            
            _buildSwitchTile(
              'Supprimer les accents',
              _commandSettings.removeAccents,
              (value) => setState(() {
                _commandSettings = _commandSettings.copyWith(removeAccents: value);
              }),
            ),
            
            _buildSwitchTile(
              'Supprimer les caractères spéciaux',
              _commandSettings.removeSpecialChars,
              (value) => setState(() {
                _commandSettings = _commandSettings.copyWith(removeSpecialChars: value);
              }),
            ),
            
            _buildSwitchTile(
              'Ajouter un préfixe',
              _commandSettings.addPrefix,
              (value) => setState(() {
                _commandSettings = _commandSettings.copyWith(addPrefix: value);
              }),
            ),
            
            if (_commandSettings.addPrefix) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Préfixe personnalisé',
                      style: GoogleFonts.inter(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _prefixController,
                      decoration: InputDecoration(
                        hintText: 'Ex: cmd_',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey[400]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Theme.of(context).primaryColor),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      style: TextStyle(color: Colors.black),
                      onChanged: (value) {
                        setState(() {
                          _commandSettings = _commandSettings.copyWith(customPrefix: value);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Aperçu en temps réel
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aperçu en temps réel',
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Commande originale: "Allumer la lumière"',
                    style: GoogleFonts.inter(color: Colors.grey[700], fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Résultat: "${normalizeCommand("Allumer la lumière")}"',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).primaryColor,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Bouton de sauvegarde
            Center(
              child: ElevatedButton(
                onPressed: () async {
                  await _commandSettingsManager.saveSettings(_commandSettings);
                  Fluttertoast.showToast(msg: 'Paramètres sauvegardés');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Sauvegarder',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      );
    },
  );
}

// Mettre à jour _buildSectionTitle pour le thème clair
Widget _buildSectionTitle(String title) {
  return Text(
    title,
    style: GoogleFonts.inter(
      color: Colors.black,
      fontWeight: FontWeight.w600,
      fontSize: 16,
    ),
  );
}

// Mettre à jour _buildSwitchTile pour le thème clair
Widget _buildSwitchTile(String title, bool value, Function(bool) onChanged) {
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            title,
            style: GoogleFonts.inter(color: Colors.black, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

Widget _buildTransformChip(String label, TextTransform transform, StateSetter setState) {
  final isSelected = _commandSettings.textTransform == transform;
  
  return FilterChip(
    label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black)),
    selected: isSelected,
    selectedColor: Theme.of(context).primaryColor,
    checkmarkColor: Colors.white,
    onSelected: (selected) {
      setState(() {
        _commandSettings = _commandSettings.copyWith(textTransform: transform);
      });
    },
  );
}

Widget _buildSpaceChip(String label, SpaceReplacement replacement, StateSetter setState) {
  final isSelected = _commandSettings.spaceReplacement == replacement;
  
  return FilterChip(
    label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black)),
    selected: isSelected,
    selectedColor: Theme.of(context).primaryColor,
    checkmarkColor: Colors.white,
    onSelected: (selected) {
      setState(() {
        _commandSettings = _commandSettings.copyWith(spaceReplacement: replacement);
      });
    },
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
        
        final wifiDevices = snapshot.data!.where((device) => device.mode == ConnectionMode.wifi).toList();
        
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
              trailing: Text(_formatDateHistory(device.lastConnected)),
              onTap: () {
                final parts = device.address.split(':');
                if (parts.length == 2) {
                  _ipController.text = parts[0];
                  _portController.text = parts[1];
                  _wifiProtocol = device.protocol as WiFiProtocol? ?? WiFiProtocol.http;
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
        
        final bluetoothDevices = snapshot.data!.where((device) => device.mode == ConnectionMode.bluetooth).toList();
        
        if (bluetoothDevices.isEmpty) {
          return const Center(child: Text('Aucun appareil Bluetooth récent'));
        }
        
        return ListView.builder(
          itemCount: bluetoothDevices.length,
          itemBuilder: (context, index) {
            final device = bluetoothDevices[index];
            return ListTile(
              leading: const Icon(Icons.bluetooth, color: Colors.blue),
              title: Text(device.name.isEmpty ? 'Appareil inconnu' : device.name),
              subtitle: Text(device.address),
              trailing: Text(_formatDateHistory(device.lastConnected)),
              onTap: () {
                final bluetoothDevice = BluetoothDevice(
                  id: device.id,
                  name: device.name,
                  isBle: device.protocol == BluetoothProtocol.ble,
                );
                final protocol = device.protocol as BluetoothProtocol? ?? BluetoothProtocol.classic;
                _connectToSelectedBluetoothDevice(bluetoothDevice, protocol);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  String _formatDateHistory(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _clearDeviceHistory() async {
    await _deviceHistoryManager.clearDeviceHistory();
    Fluttertoast.showToast(msg: "Historique des appareils effacé");
  }

 void _showPersistenceSettings() {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Paramètres',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        )),
        child: Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.height * 0.9,
              margin: const EdgeInsets.all(0),
              decoration: BoxDecoration(
                color: Colors.white, // Fond blanc
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // En-tête du dialogue
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[100], // Fond gris clair pour l'en-tête
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Paramètres',
                          style: GoogleFonts.inter(
                            color: Colors.black, // Texte noir
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.black),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Fermer',
                        ),
                      ],
                    ),
                  ),

                  // Contenu avec onglets
                  Expanded(
                    child: DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          // Barre d'onglets stylisée
                          Container(
                            margin: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: TabBar(
                              indicator: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              labelColor: Colors.white,
                              unselectedLabelColor: Colors.grey[600],
                              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
                              unselectedLabelStyle: GoogleFonts.inter(),
                              tabs: const [
                                Tab(text: 'Persistance'),
                                Tab(text: 'Commandes'),
                              ],
                            ),
                          ),

                          // Contenu des onglets
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16),
                              child: TabBarView(
                                children: [
                                  // Onglet Persistance
                                  _buildPersistenceTab(),

                                  // Onglet Commandes
                                  _buildCommandTab(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bouton Fermer en bas
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 5,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          'Fermer',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
         
  @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.grey[100],
    appBar: AppBar(
      backgroundColor: const Color.fromARGB(123, 240, 165, 236),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        _isServerMode ? 'Vocale IoT - Mode Serveur' : 'Vocale IoT Commande',
        style: GoogleFonts.interTight(
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
      centerTitle: true,
      elevation: 0,
      actions: [
        // 1. Historique des appareils
        IconButton(
          icon: const Icon(Icons.devices, color: Colors.black),
          onPressed: _showDeviceHistoryDialog,
          tooltip: 'Historique des appareils',
        ),
        
        // 2. Mode de connexion (Bluetooth/Wi-Fi)
        IconButton(
          icon: Icon(
            _connectionMode == ConnectionMode.bluetooth 
              ? Icons.bluetooth
              : _connectionMode == ConnectionMode.wifi
                  ? Icons.wifi
                  : Icons.settings_input_antenna,
            color: _isConnected && !_isServerMode 
              ? const Color.fromARGB(255, 4, 57, 252) 
              : Colors.black,
          ),
          onPressed: _isServerMode ? null : _showConnectionModeSelection,
          tooltip: _isServerMode ? 'Désactivez le mode serveur pour configurer' : 'Choisir le mode de connexion',
        ),
        
        // 3. Paramètres serveur avec indicateur de statut
        IconButton(
          icon: Stack(
            children: [
              Icon(
                Icons.cloud,
                color: _isServerMode 
                  ? (_serverConnected ? Colors.green : Colors.orange)
                  : Colors.black,
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
            ? (_serverConnected ? 'Serveur connecté - Cliquer pour configurer' : 'Serveur déconnecté - Cliquer pour configurer')
            : 'Configurer le mode serveur',
        ),
        
        // 4. Paramètres de persistance
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.black),
          onPressed: _showPersistenceSettings,
          tooltip: 'Paramètres de persistance',
        ),
      ],
    ),
    body: Column(
      children: [
        // En-tête avec état de connexion
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: _isConnected ? Colors.green[50] : Colors.orange[50],
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                _isConnected ? Icons.check_circle : Icons.warning,
                color: _isConnected ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _connectionStatus,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    if (_connectionMode == ConnectionMode.bluetooth && _selectedBluetoothDevice != null)
                      Text(
                        _selectedBluetoothDevice!.name,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                    if (_connectionMode == ConnectionMode.wifi && _wifiIp != null)
                      Text(
                        '$_wifiIp:$_wifiPort (${_wifiProtocol.name})',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                  ],
                ),
              ),
              if (_isConnected)
                IconButton(
                  icon: const Icon(Icons.link_off, color: Colors.red),
                  onPressed: _disconnect,
                  tooltip: 'Déconnecter',
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isServerMode ? _testServerConnection : () {
                  if (_connectionMode == ConnectionMode.bluetooth) {
                    _showBluetoothDeviceSelection();
                  } else if (_connectionMode == ConnectionMode.wifi) {
                    _showWifiSetupDialog();
                  }
                },
              ),
            ],
          ),
        ),

        // Contenu principal
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Bouton microphone avec animation
              GestureDetector(
                onTap: _toggleRecording,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 10,
                        color: Colors.grey.withOpacity(0.3),
                        offset: const Offset(0, 4),
                      )
                    ],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.grey[300]!,
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_isRecording)
                        Container(
                          width: 129,
                          height: 129,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.blue, Color(0xFF3A86FF)],
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: _isRecording ? Colors.transparent : Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _micEnabled ? Icons.mic : Icons.mic_off,
                          color: _isRecording ? Colors.white : Colors.black,
                          size: 64,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _isRecording ? 'Enregistrement en cours...' : 'Appuyez pour parler',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _currentCommandText,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        
        // Historique des commandes
        Container(
          height: 350,
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 212, 236, 247),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[300]!),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Historique des commandes',
                      style: GoogleFonts.interTight(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.clear_all, size: 20),
                      onPressed: () {
                        setState(() {
                          _commandHistory.clear();
                        });
                      },
                      tooltip: 'Effacer l\'historique',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (_commandHistory.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      'Aucune commande enregistrée',
                      style: GoogleFonts.inter(
                        color: Colors.grey,
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _commandHistory.length,
                    itemBuilder: (context, index) => _buildCommandItem(_commandHistory[index]),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildCommandItem(VoiceCommand command) {
  return Card(
    margin: const EdgeInsets.symmetric(vertical: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    elevation: 0,
    color: command.isResponse ? Colors.blue[50] : Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: command.isResponse 
                    ? Colors.blue[100] 
                    : (command.success ? Colors.green[100] : Colors.red[100]),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  command.isResponse 
                    ? Icons.input
                    : (command.success ? Icons.check : Icons.error),
                  color: command.isResponse 
                    ? Colors.blue[800] 
                    : (command.success ? Colors.green : Colors.red),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  command.text,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500,
                    color: command.isResponse ? Colors.blue[800] : Colors.black,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                command.mode == ConnectionMode.bluetooth
                    ? Icons.bluetooth
                    : Icons.wifi,
                color: command.mode == ConnectionMode.bluetooth
                    ? Colors.blue
                    : Colors.orange,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                command.mode == ConnectionMode.bluetooth
                    ? 'Bluetooth'
                    : 'Wi-Fi',
                style: GoogleFonts.inter(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.access_time,
                color: Colors.grey[500],
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                _formatTime(command.time),
                style: GoogleFonts.inter(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
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

        // NOUVEAU : Bouton pour ouvrir la configuration serveur complète
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
        
        // Bouton Fermer en bas du modal
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

 void _showFullServerConfigModal() {
  // Fermer d'abord le modal actuel
  Navigator.of(context).pop();
  
  // Puis ouvrir le modal de configuration serveur complet
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

String _formatTime(DateTime time) {
  final now = DateTime.now();
  final difference = now.difference(time);

  if (difference.inMinutes < 1) return 'à l\'instant';
  if (difference.inMinutes < 60) return 'il y a ${difference.inMinutes} min';
  if (difference.inHours < 24) return 'il y a ${difference.inHours} h';
  return 'il y a ${difference.inDays} j';
}
  // Les méthodes _showConnectionModeDialog, _showConnectionSettings, 
  // _showWifiSetupDialog, _showBluetoothDeviceSelection restent essentiellement les mêmes
  // mais doivent être adaptées pour utiliser les nouvelles méthodes de persistance

  void _showConnectionModeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mode de connexion'),
        content: const Text('Veuillez sélectionner un mode de connexion pour envoyer des commandes vocales'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showConnectionSettings();
            },
            child: const Text('Paramètres'),
          ),
        ],
      ),
    );
  }
   
   void _showConnectionModeSelection() {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Choisir le mode de connexion',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: Colors.black,
                ),
              ),
            ),
            const Divider(height: 1),
            // Option Bluetooth
            ListTile(
              leading: Icon(
                Icons.bluetooth,
                color: _connectionMode == ConnectionMode.bluetooth 
                    ? const Color.fromARGB(255, 4, 57, 252)
                    : Colors.grey,
              ),
              title: Text(
                'Bluetooth',
                style: GoogleFonts.inter(
                  color: Colors.black,
                  fontWeight: _connectionMode == ConnectionMode.bluetooth 
                      ? FontWeight.w600 
                      : FontWeight.normal,
                ),
              ),
              trailing: _connectionMode == ConnectionMode.bluetooth 
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.pop(context);
                _setConnectionMode(ConnectionMode.bluetooth);
                _showBluetoothDeviceSelection();
              },
            ),
            // Option Wi-Fi
            ListTile(
              leading: Icon(
                Icons.wifi,
                color: _connectionMode == ConnectionMode.wifi 
                    ? const Color.fromARGB(255, 4, 57, 252)
                    : Colors.grey,
              ),
              title: Text(
                'Wi-Fi',
                style: GoogleFonts.inter(
                  color: Colors.black,
                  fontWeight: _connectionMode == ConnectionMode.wifi 
                      ? FontWeight.w600 
                      : FontWeight.normal,
                ),
              ),
              trailing: _connectionMode == ConnectionMode.wifi 
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.pop(context);
                _setConnectionMode(ConnectionMode.wifi);
                _showWifiSetupDialog();
              },
            ),
            const SizedBox(height: 8),
            // Bouton Fermer
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                    side: const BorderSide(color: Colors.grey),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Fermer'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
  void _setConnectionMode(ConnectionMode mode) {
  setState(() {
    _connectionMode = mode;
  });
}
  void _showConnectionSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: ConnectionSettingsSheet(
          currentMode: _connectionMode,
          onModeSelected: (mode) async {
            setState(() {
              _connectionMode = mode;
            });
            
            if (mode == ConnectionMode.wifi) {
              await _showWifiSetupDialog();
            } else if (mode == ConnectionMode.bluetooth) {
              await _showBluetoothDeviceSelection();
            }
            
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Future<void> _showWifiSetupDialog() async {
    _ipController.text = _wifiIp ?? '';
    _portController.text = _wifiPort.toString();
    WiFiProtocol selectedProtocol = _wifiProtocol;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configuration Wi-Fi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<WiFiProtocol>(
              value: selectedProtocol,
              decoration: const InputDecoration(
                labelText: 'Protocole',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: WiFiProtocol.http,
                  child: Text('HTTP'),
                ),
                DropdownMenuItem(
                  value: WiFiProtocol.websocket,
                  child: Text('WebSocket'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  selectedProtocol = value;
                  _portController.text = value == WiFiProtocol.http ? '80' : '81';
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Adresse IP',
                hintText: '192.168.1.100',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '81',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final ip = _ipController.text;
              final port = int.tryParse(_portController.text) ?? 81;
              
              if (ip.isNotEmpty) {
                setState(() {
                  _wifiProtocol = selectedProtocol;
                });
                
                await _connectToWifiDevice();
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Connecter'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBluetoothDeviceSelection() async {
    BluetoothProtocol selectedProtocol = _bluetoothProtocol;
    List<BluetoothDevice> devices = [];
    bool isScanning = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Configuration Bluetooth'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Classic'),
                          selected: selectedProtocol == BluetoothProtocol.classic,
                          onSelected: (selected) {
                            setState(() {
                              selectedProtocol = BluetoothProtocol.classic;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('BLE'),
                          selected: selectedProtocol == BluetoothProtocol.ble,
                          onSelected: (selected) {
                            setState(() {
                              selectedProtocol = BluetoothProtocol.ble;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  ElevatedButton.icon(
                    icon: isScanning 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search, size: 20),
                    label: Text(isScanning ? 'Recherche en cours...' : 'Rechercher les appareils'),
                    onPressed: isScanning ? null : () async {
                      setState(() {
                        isScanning = true;
                        devices = [];
                      });
                      
                      final result = await _comService.scanBluetoothDevices(
                        protocol: selectedProtocol,
                        duration: 10,
                      );
                      
                      setState(() {
                        devices = result;
                        isScanning = false;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  
                  if (devices.isNotEmpty)
                    Text(
                      'Appareils trouvés:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      itemBuilder: (context, index) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            devices[index].isBle ? Icons.bluetooth_audio : Icons.bluetooth,
                            color: Theme.of(context).primaryColor,
                          ),
                          title: Text(devices[index].name),
                          subtitle: Text(devices[index].id),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.pop(context);
                            _connectToSelectedBluetoothDevice(devices[index], selectedProtocol);
                          },
                        ),
                      ),
                    ),
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
          );
        },
      ),
    );
  }

  // ... (les autres méthodes auxiliaires restent inchangées)
}

// ... (les classes VoiceCommand, ConnectionMode, ConnectionSettingsSheet restent inchangées)

enum ConnectionMode { none, bluetooth, wifi }

class VoiceCommand {
  final String text;
  final ConnectionMode mode;
  final DateTime time;
  final bool success;
  final bool isResponse;
  final bool isSystem;

  VoiceCommand({
    required this.text,
    required this.mode,
    required this.time,
    this.success = true,
    this.isResponse = false,
    this.isSystem = false,
  });
}

class ConnectionSettingsSheet extends StatelessWidget {
  final ConnectionMode currentMode;
  final Function(ConnectionMode) onModeSelected;

  const ConnectionSettingsSheet({
    super.key,
    required this.currentMode,
    required this.onModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Paramètres de connexion',
            style: GoogleFonts.interTight(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 24),
          _buildConnectionOption(
            context,
            icon: Icons.bluetooth,
            title: 'Bluetooth',
            mode: ConnectionMode.bluetooth,
          ),
          const SizedBox(height: 16),
          _buildConnectionOption(
            context,
            icon: Icons.wifi,
            title: 'Wi-Fi',
            mode: ConnectionMode.wifi,
          ),
          const SizedBox(height: 16),
          _buildConnectionOption(
            context,
            icon: Icons.link_off,
            title: 'Aucune connexion',
            mode: ConnectionMode.none,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Text('Fermer'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildConnectionOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required ConnectionMode mode,
  }) {
    final isSelected = currentMode == mode;
    
    return Material(
      color: isSelected 
        ? Theme.of(context).primaryColor.withOpacity(0.1) 
        : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => onModeSelected(mode),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected 
                ? Theme.of(context).primaryColor 
                : Colors.grey[300]!,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected 
                  ? Theme.of(context).primaryColor 
                  : Colors.grey[600],
                size: 28,
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected 
                    ? Theme.of(context).primaryColor 
                    : Colors.grey[800],
                ),
              ),
              const Spacer(),
              if (isSelected)
                const Icon(Icons.check_circle, color: Colors.green),
            ],
          ),
        ),
      ),
    );
  }
}