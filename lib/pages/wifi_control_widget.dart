
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:claude_iot/Wifi/http.dart';
import 'package:claude_iot/Wifi/websocket.dart';
import 'package:claude_iot/Wifi/connectivity.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:claude_iot/utils/data_saver2.dart';
import 'package:claude_iot/utils/connectW.dart';
import 'package:claude_iot/server/server_front.dart';
import 'package:claude_iot/server/server_back.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi Control Pro',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      
    );
  }
}

class FirebaseConfigScreen extends StatelessWidget {
  const FirebaseConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration Firebase')),
      body: const Center(
        child: Text('Page de configuration Firebase à implémenter'),
      ),
    );
  }
}

class WifiControlScreen extends StatefulWidget {
  const WifiControlScreen({super.key});

  @override
  State<WifiControlScreen> createState() => _WifiControlScreenState();
}

class _WifiControlScreenState extends State<WifiControlScreen> {
  late ConnectionManager _connectionManager;
  final HttpService _httpService = HttpService();
  final WebSocketService _webSocketService = WebSocketService();
  final TextEditingController _pollingCommandController = TextEditingController(
    text: 'getdata',
  
  ); // Commande par défaut pour le polling
  int _pollingIntervalSeconds = 3;

  final ConnectivityService _connectivityService = ConnectivityService();
  // Contrôleurs pour les champs de texte
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _webSocketPortController =
      TextEditingController(); // Nouveau pour le port WS
  //Message du server 
  Timer? _serverMessagesTimer;

  // Abonnements aux streams
  StreamSubscription? _connectivitySubscription;
  StreamSubscription? _webSocketMessageSubscription;
  StreamSubscription? _webSocketConnectionStatusSubscription;
  StreamSubscription?
  _httpPollingSubscription; // NOUVEL ABONNEMENT POUR LE POLLING HTTP

  bool _showConsole = false;
  // Variable pour stocker les données des capteurs
  

  // États des appareils
  bool _led1State = false;
  String _led1Name = 'LED 1';
  String _led1CommandOn = "L1";
  String _led1CommandOff = "L0";

  bool _led2State = false;
  String _led2Name = 'LED 2';
  String _led2CommandOn = "L2";
  String _led2CommandOff = "L20";

  bool _fanState = false;
  String _fanName = 'Ventilateur';
  String _fanCommandOn = "FAN";
  String _fanCommandOff = "FAN0";

  bool _tempState = false;
  String _tempName = 'Température';
  String _tempCommandOn = "TEMP";
  String _tempCommandOff = "TEMP0";

  bool _motorState = false;
  String _motorName = 'Moteur';
  String _motorCommandOn = "MOTOR";
  String _motorCommandOff = "MOTOR0";

  bool _gasState = false;
  String _gasName = 'Gaz_Sensor';
  String _gasCommandOn = "GAS";
  String _gasCommandOff = "GAS0";

  //variable pour le mode server
  bool _isServerMode = false;
  bool _serverConnected = false;
  String _serverStatusMessage = 'Non connecté au serveur';

  // État de la connexion WiFi
  bool _wifiConnected = false;
  final DataSaver2 _dataSaver = DataSaver2();
List<DeviceControl> _customDevices = [];

  // Logs de la console
  final List<String> _consoleLogs = [
    '>> Connexion établie avec 192.168.1.105:80',
    '>> Commande envoyée: L1',
    '>> Réponse: LED 1 allumée',
    '>> Commande envoyée: V1',
    '>> Réponse: Ventilateur activé',
    '>> ALERTE: Niveau de gaz élevé détecté!',
  ];

  // Couleurs personnalisées en RGBO
  final Color _primaryColor = const Color.fromRGBO(33, 150, 243, 1); // Bleu
  final Color _successColor = const Color.fromRGBO(76, 175, 80, 1); // Vert
  final Color _errorColor = const Color.fromRGBO(244, 67, 54, 1); // Rouge
  final Color _warningColor = const Color.fromRGBO(255, 193, 7, 1); // Orange
  final Color _secondaryColor = const Color.fromRGBO(156, 39, 176, 1); // Violet

  Future<void> _loadSavedSettings() async {
  final prefs = await SharedPreferences.getInstance();
  setState(() {
    _ipController.text = prefs.getString('espIp') ?? '';
    _portController.text = (prefs.getInt('espPort') ?? 80).toString();
    _webSocketPortController.text = (prefs.getInt('espWsPort') ?? 81).toString();
  });
  await _loadDefaultDevicesFromPrefs();
}

  @override
void dispose() {
  _ipController.dispose();
  _portController.dispose();
  _commandController.dispose();
  _webSocketPortController.dispose();

  // Vos abonnements existants
  _connectivitySubscription?.cancel();
  _webSocketMessageSubscription?.cancel();
  _webSocketConnectionStatusSubscription?.cancel();
  _httpPollingSubscription?.cancel();
  _serverMessagesTimer?.cancel();

  _webSocketService.dispose();
  _httpService.dispose();
  
  // Nettoyer ConnectionManager
  _connectionManager.dispose();

  super.dispose();
}

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
    _loadServerSettings();
    _loadCustomDevicesFromDisk();
    _loadConnectionHistory();
    _initializeConnectionManager();
    _loadDefaultDevicesFromPrefs();

    // Abonnement aux changements de connectivité du téléphone
    _connectivitySubscription = _connectivityService.connectionStream.listen((status) {
      setState(() {
        final isConnectedToPhoneNetwork = status.contains(ConnectivityResult.wifi) ||
            status.contains(ConnectivityResult.mobile) ||
            status.contains(ConnectivityResult.ethernet);
        _consoleLogs.add('>> État réseau téléphone: ${status.map((e) => e.toString().split('.').last).join(', ')}');
        if (!isConnectedToPhoneNetwork) {
          _wifiConnected = false;
          _webSocketService.disconnect();
          _httpService.stopPolling();
          _consoleLogs.add('>> Le téléphone a perdu sa connexion réseau.');
        }
      });
    });

    // Abonnement aux messages du WebSocket (pour recevoir les données de l'ESP)
    _webSocketMessageSubscription = _webSocketService.messages.listen((
      message,
    ) {
      setState(() {
        _consoleLogs.add('<< WS Reçu: $message');
        // TODO: Logique de parsing des messages capteurs/moniteur série ici
        // Cette partie est essentielle pour mettre à jour l'UI avec les valeurs des capteurs
        // Exemple: if (message.startsWith("TEMP:")) { _currentTemperature = double.tryParse(message.substring(5)); }
      });
    });

    // Abonnement à l'état de connexion du WebSocket
    _webSocketConnectionStatusSubscription = _webSocketService.isConnected
        .listen((connected) {
          setState(() {
            if (connected) {
              _consoleLogs.add('>> WebSocket: Connecté !');
              _wifiConnected = true;
            } else {
              _consoleLogs.add('>> WebSocket: Déconnecté !');
              _wifiConnected = false;
            }
          });
        });

    // *** NOUVEL ABONNEMENT : Pour les messages de polling HTTP ***
    _httpPollingSubscription = _httpService.pollingMessages.listen((result) {
      setState(() {
        if (result.success) {
          _consoleLogs.add('<< HTTP Reçu: ${result.message}');
          // TODO: Logique de parsing pour les données de polling HTTP ici
          // Similaire aux données WS, si l'ESP envoie "HUM:60", parsez ici.
        } else {
          _consoleLogs.add('<< HTTP Erreur: ${result.message}');
        }
      });
    });
    // *** FIN NOUVEL ABONNEMENT ***
  }

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

 // Sauvegarder tous les appareils par défaut
Future<void> _saveDefaultDevicesToPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('led1_name', _led1Name);
  await prefs.setString('led1_command_on', _led1CommandOn);
  await prefs.setString('led1_command_off', _led1CommandOff);
  
  await prefs.setString('led2_name', _led2Name);
  await prefs.setString('led2_command_on', _led2CommandOn);
  await prefs.setString('led2_command_off', _led2CommandOff);
  
  await prefs.setString('fan_name', _fanName);
  await prefs.setString('fan_command_on', _fanCommandOn);
  await prefs.setString('fan_command_off', _fanCommandOff);
  
  await prefs.setString('temp_name', _tempName);
  await prefs.setString('temp_command_on', _tempCommandOn);
  await prefs.setString('temp_command_off', _tempCommandOff);
  
  await prefs.setString('motor_name', _motorName);
  await prefs.setString('motor_command_on', _motorCommandOn);
  await prefs.setString('motor_command_off', _motorCommandOff);
  
  await prefs.setString('gas_name', _gasName);
  await prefs.setString('gas_command_on', _gasCommandOn);
  await prefs.setString('gas_command_off', _gasCommandOff);
}

// Charger tous les appareils par défaut
Future<void> _loadDefaultDevicesFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  setState(() {
    _led1Name = prefs.getString('led1_name') ?? 'LED 1';
    _led1CommandOn = prefs.getString('led1_command_on') ?? 'L1';
    _led1CommandOff = prefs.getString('led1_command_off') ?? 'L0';
    
    _led2Name = prefs.getString('led2_name') ?? 'LED 2';
    _led2CommandOn = prefs.getString('led2_command_on') ?? 'L2';
    _led2CommandOff = prefs.getString('led2_command_off') ?? 'L20';
    
    _fanName = prefs.getString('fan_name') ?? 'Ventilateur';
    _fanCommandOn = prefs.getString('fan_command_on') ?? 'FAN';
    _fanCommandOff = prefs.getString('fan_command_off') ?? 'FAN0';
    
    _tempName = prefs.getString('temp_name') ?? 'Température';
    _tempCommandOn = prefs.getString('temp_command_on') ?? 'TEMP';
    _tempCommandOff = prefs.getString('temp_command_off') ?? 'TEMP0';
    
    _motorName = prefs.getString('motor_name') ?? 'Moteur';
    _motorCommandOn = prefs.getString('motor_command_on') ?? 'MOTOR';
    _motorCommandOff = prefs.getString('motor_command_off') ?? 'MOTOR0';
    
    _gasName = prefs.getString('gas_name') ?? 'Gaz_Sensor';
    _gasCommandOn = prefs.getString('gas_command_on') ?? 'GAS';
    _gasCommandOff = prefs.getString('gas_command_off') ?? 'GAS0';
  });
}

Future<void> _loadCustomDevicesFromDisk() async {
  try {
    final result = await _dataSaver.loadControlsWithFallback(_defaultDevices);
    setState(() {
      _customDevices = result;
    });
  } catch (e) {
    _consoleLogs.add('Erreur de chargement: $e');
    setState(() {
      _customDevices = _defaultDevices;
    });
  }
}     

// Sauvegarde simplifiée
Future<void> _saveCustomDevicesToDisk() async {
  final result = await _dataSaver.saveControls(_customDevices);
  if (!result.success) {
    _consoleLogs.add('Erreur sauvegarde: ${result.error}');
  }
}

// Liste des appareils par défaut
final List<DeviceControl> _defaultDevices = [
  DeviceControl(id: 1001, name: 'Lampe', onCommand: 'ON', offCommand: 'OFF', icon: Icons.lightbulb),
  DeviceControl(id: 1002, name: 'Ventilateur', onCommand: 'FAN ON', offCommand: 'FAN OFF', icon: Icons.toys),
];

  List<Map<String, dynamic>> _connectionHistory = [];

// Charger l'historique au démarrage
Future<void> _loadConnectionHistory() async {
  final prefs = await SharedPreferences.getInstance();
  final historyJson = prefs.getString('connectionHistory');
  if (historyJson != null) {
    try {
      final List<dynamic> historyList = json.decode(historyJson);
      setState(() {
        _connectionHistory = historyList.map((item) => Map<String, dynamic>.from(item)).toList();
      });
    } catch (e) {
      _consoleLogs.add('Erreur chargement historique: $e');
    }
  }
}

// Sauvegarder une nouvelle connexion dans l'historique
Future<void> _saveToConnectionHistory(String ip, String port) async {
  final newConnection = {
    'ip': ip,
    'port': port,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'name': 'ESP32-${ip.split('.').last}' // Nom automatique
  };

  // Éviter les doublons
  final existingIndex = _connectionHistory.indexWhere(
    (conn) => conn['ip'] == ip && conn['port'] == port
  );

  if (existingIndex != -1) {
    _connectionHistory.removeAt(existingIndex);
  }

  // Ajouter au début de la liste
  _connectionHistory.insert(0, newConnection);

  // Garder seulement les 10 derniers
  if (_connectionHistory.length > 10) {
    _connectionHistory = _connectionHistory.sublist(0, 10);
  }

  // Sauvegarder dans SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('connectionHistory', json.encode(_connectionHistory));
}

  void _initializeConnectionManager() {
  _connectionManager = ConnectionManager(
    onConnectionStatusChanged: _handleConnectionStatusChanged,
    onLogMessage: _handleLogMessage,
    onReconnectStarted: _handleReconnectStarted,
    onReconnectSuccess: _handleReconnectSuccess, // Prend maintenant IP/port
    onReconnectFailed: _handleReconnectFailed,
  );
  
  _connectionManager.initialize();
}

  // Callbacks pour ConnectionManager
  void _handleConnectionStatusChanged(bool connected) {
    setState(() {
      _wifiConnected = connected;
    });
  }

  void _handleLogMessage(String message) {
  setState(() {
    _consoleLogs.add(message);
  });
  
  // Afficher les messages importants en toast
  if (message.contains('Connexion rétablie') || 
      message.contains('Échec de reconnexion') ||
      message.contains('ALERTE')) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: message.contains('ALERTE') ? _errorColor : _primaryColor,
        duration: Duration(seconds: 3),
      ),
    );
  }
}
  void _handleReconnectStarted() {
    setState(() {
      _consoleLogs.add('>> Tentative de reconnexion automatique...');
    });
  }

  void _handleReconnectSuccess(String ip, int port) {
  setState(() {
    _wifiConnected = true;
    _ipController.text = ip;
    _portController.text = port.toString();
    _showConnectionConfig = false; // Masquer après reconnexion
    _consoleLogs.add('>> Reconnexion automatique réussie à $ip:$port');
  });
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('✅ Connexion automatique réussie à $ip:$port'),
      backgroundColor: _successColor,
      duration: Duration(seconds: 3),
    ),
  );
  
  _httpService.startPolling(
    ip: ip,
    port: port,
    command: _pollingCommandController.text,
    interval: Duration(seconds: _pollingIntervalSeconds),
  );
}

void _handleReconnectFailed(String error) {
  setState(() {
    _consoleLogs.add('>> Échec reconnexion: $error');
  });
  
  // AFFICHER UN TOAST D'ERREUR
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('❌ Échec reconnexion: $error'),
      backgroundColor: _errorColor,
      duration: Duration(seconds: 3),
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromRGBO(245, 245, 245, 1),
      appBar: _buildAppBar(context),
      body: _buildBody(context),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
  return AppBar(
    title: Text(
      _isServerMode ? 'Mode Serveur' : 'Mode Wi-Fi',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
    ),
    centerTitle: true,
    backgroundColor: _primaryColor,
    foregroundColor: Colors.white,
    elevation: 2,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.of(context).pop(),
    ),
    actions: [
      // Indicateur de connexion (WiFi ou Cloud)
      Icon(
        _isServerMode 
          ? (_serverConnected ? Icons.cloud_done : Icons.cloud_off)
          : (_wifiConnected ? Icons.wifi : Icons.wifi_off),
        color: _isServerMode
          ? (_serverConnected ? Colors.white : Color.fromRGBO(255, 255, 255, 0.5))
          : (_wifiConnected ? Colors.white : Color.fromRGBO(255, 255, 255, 0.5)),
      ),
      const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.history),
          onPressed: () => _showHistoryDialog(context),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) => _handleMenuSelection(context, value),
          itemBuilder: (BuildContext context) => [
            const PopupMenuItem<String>(
              value: 'settings',
              child: Text('Paramètres avancés'),
            ),
            const PopupMenuItem<String>(
              value: 'server',
              child: Text('Configuration Server'),
            ),
            const PopupMenuItem<String>(value: 'help', child: Text('Aide')),
            const PopupMenuItem<String>(
              value: 'about',
              child: Text('À propos'),
            ),
          ],
        ),
      ],
    );
  }

  bool _showConnectionConfig = true;

// Modifiez la méthode _buildBody pour conditionner l'affichage
Widget _buildBody(BuildContext context) {
  return Column(
    children: [
      // Bandeau de statut de connexion (toujours visible)
      _buildConnectionStatusBar(context),
      
      // Configuration de connexion (conditionnelle)
      if (_showConnectionConfig) _buildConnectionCard(context),
      
      // Contenu principal avec défilement
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (!_showConnectionConfig) const SizedBox(height: 16),
              _buildControlsCard(context),
              const SizedBox(height: 100), // Espace pour la console
            ],
          ),
        ),
      ),
      // Console en bas (toujours visible)
      _buildConsoleBottomBar(context),
    ],
  );
}

  Widget _buildConnectionStatusBar(BuildContext context) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: _getConnectionStatusColor(),
      boxShadow: [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        // Icône de statut
        Icon(
          _isServerMode 
            ? (_serverConnected ? Icons.cloud_done : Icons.cloud_off)
            : (_wifiConnected ? Icons.wifi : Icons.wifi_off),
          color: Colors.white,
          size: 20,
        ),
        const SizedBox(width: 12),
        
        // Texte de statut
        Expanded(
          child: Text(
            _getConnectionStatusText(),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
        
        // Bouton pour afficher/masquer la configuration
        IconButton(
          icon: Icon(
            _showConnectionConfig ? Icons.expand_less : Icons.expand_more,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () {
            setState(() {
              _showConnectionConfig = !_showConnectionConfig;
            });
          },
          tooltip: _showConnectionConfig ? 'Masquer la configuration' : 'Afficher la configuration',
        ),
      ],
    ),
  );
}

// Méthodes helpers pour le statut
Color _getConnectionStatusColor() {
  if (_isServerMode) {
    return _serverConnected ? _successColor : _errorColor;
  } else {
    return _wifiConnected ? _successColor : _primaryColor;
  }
}

String _getConnectionStatusText() {
  if (_isServerMode) {
    return _serverConnected 
      ? 'Connecté au serveur: ${ServerBack.activeBaseUrl}'
      : 'Serveur non connecté';
  } else {
    return _wifiConnected
      ? 'Connecté à: ${_ipController.text}:${_portController.text}'
      : 'Appareil non connecté';
  }
}

  Card _buildConnectionCard(BuildContext context) {
  return Card(
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configuration de la connexion',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          
          // NOUVEAU: Switch pour basculer entre mode local et serveur
          Row(
            children: [
              Icon(Icons.cloud, color: _isServerMode ? Colors.blue : Colors.grey),
              const SizedBox(width: 8),
              Text('Mode Serveur', style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              Switch(
                value: _isServerMode,
                onChanged: _toggleServerMode,
                activeColor: Colors.blue,
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Afficher soit la config locale, soit la config serveur
          if (!_isServerMode) ...[
            _buildLocalConnectionFields(),
          ] else ...[
            _buildServerConnectionFields(),
          ],
        ],
      ),
    ),
  );
}

Widget _buildLocalConnectionFields() {
  return Column(
    children: [
      Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _ipController,
              decoration: InputDecoration(
                hintText: 'Adresse IP (ex: 192.168.1.100)',
                filled: true,
                fillColor: const Color.fromRGBO(250, 250, 250, 1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _primaryColor),
                ),
              ),
              keyboardType: TextInputType.url,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: TextField(
              controller: _portController,
              decoration: InputDecoration(
                hintText: 'Port',
                filled: true,
                fillColor: const Color.fromRGBO(250, 250, 250, 1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _primaryColor),
                ),
              ),
              keyboardType: TextInputType.number,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _buildConnectionButtons(),
    ],
  );
}

Widget _buildServerConnectionFields() {
  return Column(
    children: [
      // Statut du serveur
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _serverConnected ? Colors.green[50] : Colors.orange[50],
          borderRadius: BorderRadius.circular(8),
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
            const SizedBox(width: 8),
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
      const SizedBox(height: 12),
      _buildConnectionButtons(),
    ],
  );
}

Widget _buildConnectionButtons() {
  return Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      if (!_isServerMode) 
        OutlinedButton.icon(
          icon: Icon(Icons.search, size: 20, color: _primaryColor),
          label: Text('Détecter', style: TextStyle(color: _primaryColor)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _primaryColor),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: _scanForDevices,
        ),
      const SizedBox(width: 8),
      ElevatedButton.icon(
        icon: Icon(
          _isServerMode ? Icons.cloud : Icons.wifi, 
          size: 20
        ),
        label: Text(_getConnectionButtonText()),
        style: ElevatedButton.styleFrom(
          backgroundColor: _getConnectionButtonColor(),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: _connectToDevice,
      ),
      if (_isServerMode) ...[
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(Icons.settings, color: _primaryColor),
          onPressed: _showServerConfigModal,
          tooltip: 'Configurer le serveur',
        ),
      ],
    ],
  );
}

  Card _buildControlsCard(BuildContext context) {
    // Calcul du nombre de lignes nécessaires
    final int itemCount = 6 + _customDevices.length;
    final int rowCount = (itemCount / 3).ceil(); // Arrondi supérieur
    final double gridHeight =
        rowCount * 210.0; // 120 = hauteur estimée par ligne

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Contrôles',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.add_circle, color: _primaryColor),
                  onPressed: _addNewDevice,
                  tooltip: 'Ajouter un appareil',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Conteneur avec hauteur dynamique
            SizedBox(
              height: gridHeight,
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.65,
                children: [
                  // Appareils existants
                  _buildControlTile(
                    context,
                    icon: Icons.lightbulb,
                    title: _led1Name,
                    subtitle: _led1State ? 'ON' : 'OFF',
                    color: _led1State ? _successColor : Colors.grey,
                    commandOn: _led1CommandOn,
                    commandOff: _led1CommandOff,
                    deviceId: 1,
                  ),
                  _buildControlTile(
                    context,
                    icon: Icons.lightbulb_outline,
                    title: _led2Name,
                    subtitle: _led2State ? 'ON' : 'OFF',
                    color: _led2State ? _successColor : Colors.grey,
                    commandOn: "L2",
                    commandOff: "L2",
                    deviceId: 2,
                  ),
                  _buildControlTile(
                    context,
                    icon: Icons.air,
                    title: _fanName,
                    subtitle: _fanState ? 'ON' : 'OFF',
                    color: _fanState ? _successColor : Colors.grey,
                    commandOn: "FAN",
                    commandOff: "FAN",
                    deviceId: 3,
                  ),
                  _buildControlTile(
                    context,
                    icon: Icons.device_thermostat,
                    title: _tempName,
                    subtitle: _tempState ? 'ON' : 'OFF', // Utilise _tempState
                    color: _tempState ? _secondaryColor : Colors.grey,
                    commandOn: "TEMP",
                    commandOff: "TEMP",
                    deviceId: 4,
                  ),
                  _buildControlTile(
                    context,
                    icon: Icons.electric_bolt,
                    title: _motorName,
                    subtitle: _motorState ? 'ON' : 'OFF',
                    color: _motorState ? _successColor : Colors.grey,
                    commandOn: "MOTOR",
                    commandOff: "MOTOR",
                    deviceId: 5,
                  ),
                  _buildControlTile(
                    context,
                    icon: Icons.local_fire_department,
                    title: _gasName,
                    subtitle: _gasState ? 'ON' : 'OFF', // Utilise _gasState
                    color: _gasState ? _successColor : Colors.grey,
                    commandOn: "GAS",
                    commandOff: "GAS0",
                    deviceId: 6,
                  ),

                  // Appareils personnalisés
                 // ...existing code...
..._customDevices.map(
  (device) => _buildControlTile(
    context,
    icon: device.icon,
    title: device.name,
    subtitle: device.isActive ? 'ON' : 'OFF',
    color: device.isActive ? _successColor : Colors.grey,
    commandOn: device.onCommand,
    commandOff: device.offCommand,
    isCustom: true,
    deviceId: device.id, // Utilise device.id
  ),
),
// ...existing code...
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlTile(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required Color color,
  String? commandOn,
  String? commandOff,
  bool isCustom = false,
  required int deviceId,
}) {
  return Material(
    elevation: 2,
    borderRadius: BorderRadius.circular(16),
    color: Colors.white,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        // Vérifier la connexion selon le mode
        if (_isServerMode) {
          if (!_serverConnected) {
            setState(() {
              _consoleLogs.add('>> Erreur: Serveur non connecté.');
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Serveur non connecté. Tentative de reconnexion...'),
                backgroundColor: _errorColor,
              ),
            );
            
            await _testServerConnection();
            return;
          }
        } else {
          if (!_connectionManager.isConnected) {
            setState(() {
              _consoleLogs.add('>> Erreur: Aucun appareil connecté.');
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Aucun appareil connecté. Tentative de reconnexion...'),
                backgroundColor: _errorColor,
              ),
            );
            
            await _attemptAutoReconnect();
            return;
          }
        }

        String commandToSend = "";
        bool? newState;

        setState(() {
          if (isCustom) {
            final deviceIndex = _customDevices.indexWhere((d) => d.id == deviceId);
            if (deviceIndex != -1) {
              newState = !_customDevices[deviceIndex].isActive;
              _customDevices[deviceIndex].isActive = newState!;
              commandToSend = newState! ? commandOn! : commandOff!;
            }
          } else {
            // Gestion des appareils prédéfinis
            switch (deviceId) {
              case 1:
                _led1State = !_led1State;
                newState = _led1State;
                commandToSend = _led1State ? commandOn! : commandOff!;
                break;
              case 2:
                _led2State = !_led2State;
                newState = _led2State;
                commandToSend = _led2State ? commandOn! : commandOff!;
                break;
              case 3:
                _fanState = !_fanState;
                newState = _fanState;
                commandToSend = _fanState ? commandOn! : commandOff!;
                break;
              case 4:
                _tempState = !_tempState;
                newState = _tempState;
                commandToSend = _tempState ? commandOn! : commandOff!;
                break;
              case 5:
                _motorState = !_motorState;
                newState = _motorState;
                commandToSend = _motorState ? commandOn! : commandOff!;
                break;
              case 6:
                _gasState = !_gasState;
                newState = _gasState;
                commandToSend = _gasState ? commandOn! : commandOff!;
                break;
            }
          }
          _consoleLogs.add('>> Commande: $commandToSend');
        });

        // Utiliser la nouvelle méthode qui gère les deux modes
        await _sendDeviceCommand(commandToSend, deviceId: deviceId);

        // Si l'envoi a échoué, annuler le changement d'état
        // La logique d'annulation est maintenant dans _sendDeviceCommand
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1.5),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: Colors.grey[500],
                  ),
                  onPressed: () => _showDeviceOptions(context, deviceId),
                ),
              ],
            ),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    ),
  );
}

  // ========== Méthodes d'actions ========== //
  // Ces méthodes doivent être implémentées dans un fichier service séparé

  void _scanForDevices() {
    print('Scan des appareils en cours...');
    setState(() {
      _wifiConnected = true;
      _consoleLogs.add('>> Scan terminé - 3 appareils trouvés');
    });
  }

  void _connectToDevice() async {
  if (_isServerMode) {
    await _testServerConnection();
    if (_serverConnected) {
      setState(() {
        _showConnectionConfig = false; // Masquer après connexion réussie
      });
      _consoleLogs.add('>> ✅ Connexion serveur établie: ${ServerBack.activeBaseUrl}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Connecté au serveur'),
          backgroundColor: _successColor,
        ),
      );
    }
  } else {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 80;

    if (ip.isEmpty || port == 0) {
      setState(() {
        _consoleLogs.add('>> Erreur: Veuillez entrer une IP et un port valides.');
        _wifiConnected = false;
      });
      return;
    }

    final success = await _connectionManager.connect(ip, port);
    
    if (success) {
      setState(() {
        _showConnectionConfig = false; // Masquer après connexion réussie
      });
      await _saveToConnectionHistory(ip, port.toString());
      _httpService.startPolling(
        ip: ip,
        port: port,
        command: _pollingCommandController.text,
        interval: Duration(seconds: _pollingIntervalSeconds),
      );
    }
  }
}

  // Ajouter cette méthode pour récupérer les messages du serveur
 Future<void> _fetchServerMessages() async {
  if (!_isServerMode || !_serverConnected) return;

  print('🔄 Fetching messages from: ${ServerBack.activeBaseUrl}/messages');
  
  final result = await ServerBack.getMessages();
  
  print('📡 Server response: $result');
  print('📡 Type of result: ${result.runtimeType}');
  print('📡 success value: ${result['success']}');
  print('📡 success type: ${result['success'].runtimeType}');
  print('📡 success == true: ${result['success'] == true}');
  
  setState(() {
    if (result['success'] == true) {
      final List<dynamic> newMessages = result['messages'] ?? [];
      print('📨 Messages received: ${newMessages.length}');
      
      for (var message in newMessages) {
        final String formattedMessage = _formatServerMessage(message);
        if (!_consoleLogs.any((log) => log.contains(formattedMessage))) {
          _consoleLogs.add('<< Serveur: $formattedMessage');
        }
      }
      
    } else {
      final errorMsg = result['message'] ?? 'Unknown error';
      print('❌ ENTERING ERROR BLOCK - Error message: $errorMsg');
      _consoleLogs.add('>> Erreur récupération messages: $errorMsg');
    }
  });
}

// Nouvelle méthode pour formater les messages serveur
String _formatServerMessage(dynamic message) {
  try {
    if (message is Map) {
      final deviceId = message['device_id']?.toString() ?? 'Inconnu';
      final messageText = message['message']?.toString() ?? 'Pas de message';
      final createdAt = message['created_at']?.toString() ?? '';
      
      // Formater la date pour plus de lisibilité
      String formattedDate = _formatDate(createdAt);
      
      // Retourner seulement le message et la date formatée
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

// Méthode pour formater la date
String _formatDate(String isoDate) {
  try {
    if (isoDate.isEmpty) return '';
    
    final date = DateTime.parse(isoDate);
    
    // Convertir UTC en heure locale
    final localDate = date.toLocal();
    
    // Formater en français : JJ/MM/AAAA HH:MM:SS
    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final year = localDate.year.toString();
    final hour = localDate.hour.toString().padLeft(2, '0');
    final minute = localDate.minute.toString().padLeft(2, '0');
    final second = localDate.second.toString().padLeft(2, '0');
    
    return '$day/$month/$year $hour:$minute:$second';
  } catch (e) {
    return ''; // Retourner une chaîne vide si la date ne peut pas être parsée
  }
}

// Démarrer le polling des messages serveur
void _startServerMessagesPolling() {
  _serverMessagesTimer?.cancel();
  _serverMessagesTimer = Timer.periodic(Duration(seconds: 3), (timer) {
    if (_isServerMode && _serverConnected) {
      _fetchServerMessages();
    }
  });
}

// Arrêter le polling
void _stopServerMessagesPolling() {
  _serverMessagesTimer?.cancel();
  _serverMessagesTimer = null;
}

  void _sendCommand() async {
  final command = _commandController.text.trim();
  
  if (command.isEmpty) {
    setState(() {
      _consoleLogs.add('>> Erreur: Commande vide.');
    });
    return;
  }

  setState(() {
    _consoleLogs.add('>> Envoi: $command');
    _commandController.clear();
  });

  // Utilisez la nouvelle méthode qui gère les deux modes
  await _sendDeviceCommand(command);
}

  Future<void> _sendDeviceCommand(String command, {int? deviceId}) async {
  bool? originalState;
  
  // Sauvegarder l'état original pour annulation si nécessaire
  // (Cette logique devrait être gérée dans l'appelant)

  if (_isServerMode && _serverConnected) {
    // Envoi via le serveur
    final result = await ServerBack.sendCommand(command);
    
    setState(() {
      if (result['success'] == true) {
        _consoleLogs.add('>> ✅ Commande envoyée au serveur: $command');
        _consoleLogs.add('>> 📡 Réponse serveur: ${result['message']}');
      } else {
        _consoleLogs.add('>> ❌ Erreur serveur: ${result['message']}');
        // Annuler le changement d'état visuel en cas d'erreur
        _revertDeviceState(deviceId, originalState);
      }
    });
    
  } else if (!_isServerMode && _wifiConnected) {
    // Envoi local
    final ip = _ipController.text.trim().isEmpty 
        ? await _getLastConnectedIP() 
        : _ipController.text.trim();
        
    final port = _portController.text.trim().isEmpty 
        ? await _getLastConnectedPort() 
        : int.tryParse(_portController.text.trim()) ?? 80;

    if (ip.isEmpty || port == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ IP ou Port manquant.')),
      );
      _revertDeviceState(deviceId, originalState);
      return;
    }

    final result = await _httpService.sendCommand(
      ip: ip,
      port: port,
      command: command,
    );

    setState(() {
      if (result.success) {
        _consoleLogs.add('>> Réponse ESP: ${result.message}');
      } else {
        _consoleLogs.add('>> Erreur envoi ESP: ${result.message}');
        _revertDeviceState(deviceId, originalState);
      }
    });
  } else {
    // Aucune connexion disponible
    setState(() {
      _consoleLogs.add('>> ❌ Erreur: Aucune connexion active');
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ Aucune connexion active'),
        backgroundColor: _errorColor,
      ),
    );
    _revertDeviceState(deviceId, originalState);
  }
}

// Méthode helper pour annuler les changements d'état en cas d'erreur
void _revertDeviceState(int? deviceId, bool? originalState) {
  if (deviceId != null && originalState != null) {
    setState(() {
      // Logique pour revenir à l'état précédent
      // À implémenter selon la structure de vos devices
    });
  }
}

  void _addNewDevice() {
    String deviceName = '';
    IconData selectedIcon = Icons.sensors;
    Color selectedColor = _warningColor;
    String deviceCommandOn = '';
    String deviceCommandOff = '';

    final List<IconData> iconChoices = [
      Icons.sensors,
      Icons.thermostat,
      Icons.lightbulb,
      Icons.lightbulb_outline,
      Icons.air,
      Icons.local_fire_department,
      Icons.electric_bolt,
      Icons.sensors_off,
      Icons.speaker,
      Icons.speaker_group,
      Icons.router,
      Icons.wifi,
      Icons.memory,
      Icons.door_front_door,
      Icons.lock,
      Icons.camera_alt,
      Icons.tv,
      Icons.kitchen,
      Icons.water_drop,
      Icons.bolt,
    ];

    // Création d'un ScrollController pour la grille des icônes
    final ScrollController _iconScrollController = ScrollController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ajouter un appareil personnalisé',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Nom du capteur',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => deviceName = value,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Commande ON (ex: L3:1)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => deviceCommandOn = value,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Commande OFF (ex: L3:0)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => deviceCommandOff = value,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Icône :',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),

                        // Correction du défilement des icônes
                        Container(
                          height: 160,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Scrollbar(
                            controller: _iconScrollController,
                            thumbVisibility: true,
                            child: GridView.count(
                              controller: _iconScrollController,
                              crossAxisCount: 5,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              padding: const EdgeInsets.all(8),
                              children: iconChoices.map((iconData) {
                                return GestureDetector(
                                  onTap: () => setStateDialog(
                                    () => selectedIcon = iconData,
                                  ),
                                  child: CircleAvatar(
                                    backgroundColor: selectedIcon == iconData
                                        ? _primaryColor.withOpacity(0.15)
                                        : Colors.grey[200],
                                    child: Icon(
                                      iconData,
                                      color: selectedIcon == iconData
                                          ? _primaryColor
                                          : Colors.grey[700],
                                      size: 28,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                        Text(
                          'Couleur :',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildColorOption(
                              _successColor,
                              selectedColor,
                              setStateDialog,
                            ),
                            const SizedBox(width: 12),
                            _buildColorOption(
                              _primaryColor,
                              selectedColor,
                              setStateDialog,
                            ),
                            const SizedBox(width: 12),
                            _buildColorOption(
                              _warningColor,
                              selectedColor,
                              setStateDialog,
                            ),
                            const SizedBox(width: 12),
                            _buildColorOption(
                              _errorColor,
                              selectedColor,
                              setStateDialog,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Annuler'),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: () {
                                if (deviceName.trim().isEmpty ||
                                    deviceCommandOn.trim().isEmpty ||
                                    deviceCommandOff.trim().isEmpty) {
                                  return;
                                }

                              
                     setState(() {
                     _customDevices.add(
                     DeviceControl(
                     id: DateTime.now().millisecondsSinceEpoch, // id unique
                     name: deviceName,
                     onCommand: deviceCommandOn,
                    offCommand: deviceCommandOff,
                   icon: selectedIcon,
                ),
                  );
               _consoleLogs.add('>> Nouvel appareil ajouté: $deviceName');
                });
                          _saveCustomDevicesToDisk();
                                Navigator.pop(context);
                              },
                              child: const Text('Ajouter'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildColorOption(
    Color color,
    Color selectedColor,
    Function setStateDialog,
  ) {
    return GestureDetector(
      onTap: () => setStateDialog(() => selectedColor = color),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selectedColor == color
              ? Border.all(color: Colors.black, width: 2)
              : null,
        ),
        child: selectedColor == color
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }

  void _showDeviceOptions(BuildContext context, int deviceId) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Renommer'),
              onTap: () {
                Navigator.pop(context);
                _renameDevice(deviceId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.code, color: Colors.green),
              title: const Text('Modifier commandes'),
              onTap: () {
                Navigator.pop(context);
                _editDeviceCommands(deviceId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Supprimer'),
              onTap: () {
                Navigator.pop(context);
                _deleteDevice(deviceId);
              },
            ),
          ],
        );
      },
    );
  }

  void _renameDevice(int deviceId) async {
    String newName = '';
    String currentName = '';

    // Déterminer le nom actuel en fonction de l'ID
    switch (deviceId) {
      case 1:
        currentName = _led1Name;
        break;
      case 2:
        currentName = _led2Name;
        break;
      case 3:
        currentName = _fanName;
        break;
      case 4:
        currentName = _tempName;
        break;
      case 5:
        currentName = _motorName;
        break;
      case 6:
        currentName = _gasName;
        break;
      default:
        return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer l\'appareil'),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(hintText: currentName),
          onChanged: (value) => newName = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newName.trim().isNotEmpty) {
                setState(() {
                  switch (deviceId) {
                    case 1:
                      _led1Name = newName;
                      break;
                    case 2:
                      _led2Name = newName;
                      break;
                    case 3:
                      _fanName = newName;
                      break;
                    case 4:
                      _tempName = newName;
                      break;
                    case 5:
                      _motorName = newName;
                      break;
                    case 6:
                      _gasName = newName;
                      break;
                  }
                  _consoleLogs.add('>> Appareil renommé: $newName');
                });
                await _saveDefaultDevicesToPrefs();
              }
              Navigator.pop(context);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  void _editDeviceCommands(int deviceId) async {
    String commandOn = '';
    String commandOff = '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier les commandes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Commande ON',
                hintText: _getCommandOnHint(deviceId),
              ),
              onChanged: (value) => commandOn = value,
            ),
            TextField(
              decoration: InputDecoration(
                labelText: 'Commande OFF',
                hintText: _getCommandOffHint(deviceId),
              ),
              onChanged: (value) => commandOff = value,
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
              setState(() {
                if (commandOn.isNotEmpty) {
                  switch (deviceId) {
                    case 1:
                      _led1CommandOn = commandOn;
                      break;
                    case 2:
                      _led2CommandOn = commandOn;
                      break;
                    case 3:
                      _fanCommandOn = commandOn;
                      break;
                    case 4:
                      _tempCommandOn = commandOn;
                      break;
                    case 5:
                      _motorCommandOn = commandOn;
                      break;
                    case 6:
                      _gasCommandOn = commandOn;
                      break;
                  }
                }
                if (commandOff.isNotEmpty) {
                  switch (deviceId) {
                    case 1:
                      _led1CommandOff = commandOff;
                      break;
                    case 2:
                      _led2CommandOff = commandOff;
                      break;
                    case 3:
                      _fanCommandOff = commandOff;
                      break;
                    case 4:
                      _tempCommandOff = commandOff;
                      break;
                    case 5:
                      _motorCommandOff = commandOff;
                      break;
                    case 6:
                      _gasCommandOff = commandOff;
                      break;
                  }
                }
                _consoleLogs.add(
                  '>> Commandes modifiées pour l\'appareil $deviceId',
                );
              });
              await _saveDefaultDevicesToPrefs();
              Navigator.pop(context);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  // Fonctions d'aide pour les hints
  String _getCommandOnHint(int deviceId) {
    switch (deviceId) {
      case 1:
        return _led1CommandOn;
      case 2:
        return _led2CommandOn;
      case 3:
        return _fanCommandOn;
      case 4:
        return _tempCommandOn;
      case 5:
        return _motorCommandOn;
      case 6:
        return _gasCommandOn;
      default:
        return '';
    }
  }

  String _getCommandOffHint(int deviceId) {
    switch (deviceId) {
      case 1:
        return _led1CommandOff;
      case 2:
        return _led2CommandOff;
      case 3:
        return _fanCommandOff;
      case 4:
        return _tempCommandOff;
      case 5:
        return _motorCommandOff;
      case 6:
        return _gasCommandOff;
      default:
        return '';
    }
  }

  void _deleteDevice(int deviceId) {
    if (deviceId >= 1 && deviceId <= 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de supprimer un appareil système'),
        ),
      );
    } else {
      setState(() {
        _customDevices.removeWhere((d) => d.toJson()['id'] == deviceId);
        _consoleLogs.add('>> Appareil supprimé');
      });
      _saveCustomDevicesToDisk();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Appareil supprimé')));
    }
  }

  void _showHistoryDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Historique des connexions'),
      content: SizedBox(
        width: double.maxFinite,
        child: _connectionHistory.isEmpty
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Aucun appareil enregistré',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Les appareils auxquels vous vous connectez apparaîtront ici',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _connectionHistory.length,
                itemBuilder: (context, index) {
                  final connection = _connectionHistory[index];
                  final date = DateTime.fromMillisecondsSinceEpoch(connection['timestamp']);
                  final formattedDate = '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
                  
                  return ListTile(
                    leading: const Icon(Icons.wifi, color: Colors.blue),
                    title: Text(connection['name'] ?? 'Appareil inconnu'),
                    subtitle: Text('${connection['ip']}:${connection['port']}\n$formattedDate'),
                    trailing: IconButton(
                      icon: const Icon(Icons.connect_without_contact),
                      onPressed: () => _connectToHistoryDevice(connection['ip'], connection['port']),
                    ),
                    onLongPress: () => _showDeleteHistoryDialog(context, index),
                  );
                },
              ),
      ),
      actions: [
        if (_connectionHistory.isNotEmpty)
          TextButton(
            onPressed: () => _showClearHistoryDialog(context),
            child: const Text('Tout effacer', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}


  void _connectToHistoryDevice(String ip, String port) {
  setState(() {
    _ipController.text = ip;
    _portController.text = port;
    _consoleLogs.add('>> Appareil historique chargé: $ip:$port');
  });
  Navigator.pop(context);
  
  // Optionnel: connexion automatique
  // _connectToDevice();
}

void _showDeleteHistoryDialog(BuildContext context, int index) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Supprimer de l\'historique'),
      content: Text('Voulez-vous supprimer ${_connectionHistory[index]['ip']} de l\'historique ?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _connectionHistory.removeAt(index);
              _saveConnectionHistoryToPrefs();
            });
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Appareil supprimé de l\'historique')),
            );
          },
          child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

void _showClearHistoryDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Effacer tout l\'historique'),
      content: const Text('Voulez-vous supprimer tout l\'historique des connexions ?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _connectionHistory.clear();
              _saveConnectionHistoryToPrefs();
            });
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Historique effacé')),
            );
          },
          child: const Text('Effacer tout', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

Future<void> _saveConnectionHistoryToPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('connectionHistory', json.encode(_connectionHistory));
}

  void _handleMenuSelection(BuildContext context, String value) {
    switch (value) {
      case 'settings':
        _showAdvancedSettings(context);
        break;
      case 'server':
        Navigator.pushNamed(context, '/server');
        break;
      case 'help':
        _showHelp(context);
        break;
      case 'about':
        _showAbout(context);
        break;
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
      _consoleLogs.add('>> ✅ Connecté au serveur: ${ServerBack.activeBaseUrl}');
      // Démarrer le polling des messages
      _startServerMessagesPolling();
      // Récupérer les messages immédiatement
      _fetchServerMessages();
    } else {
      _consoleLogs.add('>> ❌ Erreur serveur: ${result['message']}');
      _stopServerMessagesPolling();
    }
  });
}

void _toggleServerMode(bool value) async {
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
    _stopServerMessagesPolling(); // Arrêter le polling serveur
  } else {
    _testServerConnection(); // Cela démarrera automatiquement le polling
  }
}

String _getConnectionButtonText() {
  if (_isServerMode) {
    return _serverConnected ? 'Serveur Connecté' : 'Connecter Serveur';
  } else {
    return _wifiConnected ? 'Connecté' : 'Connecter';
  }
}

Color _getConnectionButtonColor() {
  if (_isServerMode) {
    return _serverConnected ? _successColor : _primaryColor;
  } else {
    return _wifiConnected ? _successColor : _primaryColor;
  }
}

// Remplacez toute la méthode _buildServerConfigModal() par:
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
            BoxShadow(
              blurRadius: 20,
              color: Colors.black.withOpacity(0.2),
            ),
          ],
        ),
        child: ServerFront(),
      ),
    ),
  );
}

  // Ajouter dans _WifiControlScreenState
Future<String> _getLastConnectedIP() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('lastConnectedIP') ?? '';
}

Future<int> _getLastConnectedPort() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt('lastConnectedPort') ?? 80;
}

Future<void> _attemptAutoReconnect() async {
  final ip = await _getLastConnectedIP();
  final port = await _getLastConnectedPort();
  
  if (ip.isNotEmpty && port != 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔄 Tentative de reconnexion automatique...'),
        backgroundColor: _warningColor,
      ),
    );
    
    final success = await _connectionManager.connect(ip, port);
    if (success) {
      setState(() {
        _ipController.text = ip;
        _portController.text = port.toString();
      });
    }
  }
}

  void _showAdvancedSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paramètres avancés'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAdvancedSettingItem(
                context,
                icon: Icons.security,
                title: 'Sécurité',
                subtitle: 'Paramètres de sécurité WiFi',
                onTap: () => _showSecuritySettings(),
              ),
              _buildAdvancedSettingItem(
                context,
                icon: Icons.timer,
                title: 'Délai de connexion',
                subtitle: 'Configurer les timeouts',
                onTap: () => _showTimeoutSettings(),
              ),
              _buildAdvancedSettingItem(
                context,
                icon: Icons.notifications,
                title: 'Notifications',
                subtitle: 'Configurer les alertes',
                onTap: () => _showNotificationSettings(),
              ),
              _buildAdvancedSettingItem(
                context,
                icon: Icons.backup,
                title: 'Sauvegarde',
                subtitle: 'Sauvegarder la configuration',
                onTap: () => _backupConfiguration(),
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

  Widget _buildAdvancedSettingItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: _primaryColor),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }

  void _showSecuritySettings() {
    print('Affichage des paramètres de sécurité');
  }

  void _showTimeoutSettings() {
    print('Affichage des paramètres de délai');
  }

  void _showNotificationSettings() {
    print('Affichage des paramètres de notification');
  }

  void _backupConfiguration() {
    print('Sauvegarde de la configuration');
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aide'),
        content: const Text(
          'Instructions pour utiliser l\'interface Wi-Fi:\n\n'
          '1. Entrez l\'adresse IP et le port de l\'appareil\n'
          '2. Cliquez sur "Connecter" pour établir la connexion\n'
          '3. Utilisez les interrupteurs pour contrôler les appareils\n'
          '4. Envoyez des commandes manuelles dans la console\n\n'
          'Pour plus d\'aide, contactez le support technique.',
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

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('À propos'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('WiFi Control Pro'),
            SizedBox(height: 8),
            Text('Version 1.0.0'),
            SizedBox(height: 8),
            Text('© 2023 Votre Entreprise'),
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

  Widget _buildConsoleBottomBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: const Border(top: BorderSide(color: Colors.blue, width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bandeau supérieur de la console
          GestureDetector(
            onTap: () => setState(() => _showConsole = !_showConsole),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.code, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Console',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.blue,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showConsole ? Icons.expand_less : Icons.expand_more,
                    color: Colors.blue,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.blue, size: 20),
                    tooltip: 'Effacer la console',
                    onPressed: () => setState(() => _consoleLogs.clear()),
                  ),
                ],
              ),
            ),
          ),

          // Partie détaillée de la console
          if (_showConsole) ...[
            Container(
              color: const Color(0xFFEDF4FF),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 170,
                    child: ListView.builder(
                      reverse: true,
                      itemCount: _consoleLogs.length,
                      itemBuilder: (context, index) {
                        final log =
                            _consoleLogs[_consoleLogs.length - 1 - index];
                        final bool isServerMessage = log.startsWith('<< Serveur:');
                        final bool isMicrocontroller = log.startsWith('<< WS Reçu:') || log.startsWith('<< HTTP Reçu:');    
                        final bool isAlert = log.contains('ALERTE');
                        final bool isConnection = log.contains('Connexion');

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              color: isMicrocontroller // Priorité aux messages du microcontrôleur
                                ? const Color.fromARGB(255, 16, 13, 161)
                              : isServerMessage
                                    ? Colors.purple
                              : isAlert
                                  ? _errorColor
                                  : isConnection
                                  ? _successColor
                                  : Colors.black87,
                              fontWeight: isMicrocontroller
                                  ? FontWeight.bold
                                  : isAlert
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commandController,
                          decoration: InputDecoration(
                            hintText: 'Commande manuelle (ex: L1)',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: _primaryColor),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.send, size: 20),
                        label: const Text('Envoyer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                        ),
                        onPressed: _sendCommand,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DeviceControl {
  int id; // Ajoute ce champ
  String name;
  String onCommand;
  String offCommand;
  IconData icon;
  bool isActive;

  DeviceControl({
    required this.id, // Ajoute ce paramètre
    required this.name,
    required this.onCommand,
    required this.offCommand,
    required this.icon,
    this.isActive = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id, // Ajoute l'id ici
      'name': name,
      'onCommand': onCommand,
      'offCommand': offCommand,
      'iconCodePoint': icon.codePoint,
      'iconFontFamily': icon.fontFamily,
      'isActive': isActive,
    };
  }

  factory DeviceControl.fromJson(Map<String, dynamic> json) {
    final iconCodePoint = json['iconCodePoint'];
    final iconFontFamily = json['iconFontFamily'];
    final IconData iconData = (iconCodePoint != null && iconFontFamily != null)
        ? IconData(iconCodePoint as int, fontFamily: iconFontFamily as String)
        : Icons.device_unknown;

    return DeviceControl(
      id: json['id'] as int? ?? 0, // Ajoute la récupération de l'id
      name: json['name'] as String,
      onCommand: json['onCommand'] as String,
      offCommand: json['offCommand'] as String,
      icon: iconData,
      isActive: json['isActive'] as bool? ?? false,
    );
  }
}