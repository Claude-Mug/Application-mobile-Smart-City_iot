
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:claude_iot/Wifi/http.dart';
import 'package:claude_iot/Wifi/websocket.dart';
import 'package:claude_iot/Wifi/connectivity.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      initialRoute: '/',
      routes: {
        '/': (context) => const WifiControlScreen(),
        '/firebase': (context) =>
            const FirebaseConfigScreen(), // Route pour Firebase
      },
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
  String _led1CommandOn = "L1:1";
  String _led1CommandOff = "L1:0";

  bool _led2State = false;
  String _led2Name = 'LED 2';
  String _led2CommandOn = "L2:1";
  String _led2CommandOff = "L2:0";

  bool _fanState = false;
  String _fanName = 'Ventilateur';
  String _fanCommandOn = "FAN:1";
  String _fanCommandOff = "FAN:0";

  bool _tempState = false;
  String _tempName = 'Température';
  String _tempCommandOn = "TEMP:1";
  String _tempCommandOff = "TEMP:0";

  bool _motorState = false;
  String _motorName = 'Moteur';
  String _motorCommandOn = "MOTOR:1";
  String _motorCommandOff = "MOTOR:0";

  bool _gasState = false;
  String _gasName = 'Gaz_Sensor';
  String _gasCommandOn = "GAS:1";
  String _gasCommandOff = "GAS:0";

  // État de la connexion WiFi
  bool _wifiConnected = false;
  final List<Map<String, dynamic>> _customDevices = [];

  // Logs de la console
  final List<String> _consoleLogs = [
    '>> Connexion établie avec 192.168.1.105:80',
    '>> Commande envoyée: L1:1',
    '>> Réponse: LED 1 allumée',
    '>> Commande envoyée: V1:1',
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
}

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _commandController.dispose();
    _webSocketPortController.dispose();

    _connectivitySubscription?.cancel();
    _webSocketMessageSubscription?.cancel();
    _webSocketConnectionStatusSubscription?.cancel();
    _httpPollingSubscription
        ?.cancel(); // NOUVEAU : Annuler l'abonnement du polling HTTP

    _webSocketService.dispose();
    _httpService
        .dispose(); // Très important pour arrêter le timer du polling et fermer les streams HTTP
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();

    // Abonnement aux changements de connectivité du téléphone
    _connectivitySubscription = _connectivityService.connectionStream.listen((
      status,
    ) {
      setState(() {
        final isConnectedToPhoneNetwork =
            status.contains(ConnectivityResult.wifi) ||
            status.contains(ConnectivityResult.mobile) ||
            status.contains(ConnectivityResult.ethernet);
        _consoleLogs.add(
          '>> État réseau téléphone: ${status.map((e) => e.toString().split('.').last).join(', ')}',
        );
        if (!isConnectedToPhoneNetwork) {
          _wifiConnected = false;
          _webSocketService.disconnect();
          _httpService
              .stopPolling(); // Arrêter le polling HTTP si le téléphone perd sa connexion
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
      title: const Text(
        'Mode Wi-Fi',
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
        // Indicateur de connexion WiFi
        Icon(
          _wifiConnected ? Icons.wifi : Icons.wifi_off,
          color: _wifiConnected
              ? Colors.white
              : const Color.fromRGBO(255, 255, 255, 0.5),
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
              value: 'firebase',
              child: Text('Configuration Firebase'),
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

  Widget _buildBody(BuildContext context) {
    return Column(
      children: [
        // Contenu principal avec défilement
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildConnectionCard(context),
                const SizedBox(height: 16),
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: Icon(Icons.search, size: 20, color: _primaryColor),
                  label: Text(
                    'Détecter',
                    style: TextStyle(color: _primaryColor),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: _scanForDevices,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.wifi, size: 20),
                  label: Text(_wifiConnected ? 'Connecté' : 'Connecter'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _wifiConnected
                        ? _successColor
                        : _primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: _connectToDevice,
                ),
              ],
            ),
          ],
        ),
      ),
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
                    commandOn: "L2:1",
                    commandOff: "L2:0",
                    deviceId: 2,
                  ),
                  _buildControlTile(
                    context,
                    icon: Icons.air,
                    title: _fanName,
                    subtitle: _fanState ? 'ON' : 'OFF',
                    color: _fanState ? _successColor : Colors.grey,
                    commandOn: "FAN:1",
                    commandOff: "FAN:0",
                    deviceId: 3,
                  ),
                  _buildControlTile(
                    context,
                    icon: Icons.device_thermostat,
                    title: _tempName,
                    subtitle: _tempState ? 'ON' : 'OFF', // Utilise _tempState
                    color: _tempState ? _secondaryColor : Colors.grey,
                    commandOn: "TEMP:1",
                    commandOff: "TEMP:0",
                    deviceId: 4,
                  ),
                  _buildControlTile(
                    context,
                    icon: Icons.electric_bolt,
                    title: _motorName,
                    subtitle: _motorState ? 'ON' : 'OFF',
                    color: _motorState ? _successColor : Colors.grey,
                    commandOn: "MOTOR:1",
                    commandOff: "MOTOR:0",
                    deviceId: 5,
                  ),
                  _buildControlTile(
                    context,
                    icon: Icons.local_fire_department,
                    title: _gasName,
                    subtitle: _gasState ? 'ON' : 'OFF', // Utilise _gasState
                    color: _gasState ? _successColor : Colors.grey,
                    commandOn: "GAS:1",
                    commandOff: "GAS:0",
                    deviceId: 6,
                  ),

                  // Appareils personnalisés
                  ..._customDevices.map(
                    (device) => _buildControlTile(
                      context,
                      icon: device['icon'],
                      title: device['name'],
                      subtitle: device['state'] ? 'ON' : 'OFF',
                      color: device['state'] ? device['color'] : Colors.grey,
                      commandOn: device['commandOn'],
                      commandOff: device['commandOff'],
                      isCustom: true,
                      deviceId: device['id'],
                    ),
                  ),
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
          // Rendre la fonction asynchrone
          final ip = _ipController.text.trim();
          final port = int.tryParse(_portController.text.trim()) ?? 80;

          // Vérification stricte : IP et Port doivent être renseignés
          if (ip.isEmpty || port == 0) {
            setState(() {
              _consoleLogs.add(
                '>> Erreur: Aucun appareil connecté. Veuillez renseigner l\'IP et le Port.',
              );
              // Optionnel: Afficher un SnackBar pour une visibilité immédiate
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Aucun appareil connecté. Renseignez l\'IP et le Port.',
                  ),
                ),
              );
            });
            return; // Arrêter l'exécution si l'IP ou le port est manquant
          }

          // Vérifier si le téléphone a une connectivité réseau active (Wi-Fi ou mobile pour hotspot)
          final List<ConnectivityResult> currentConnections =
              await _connectivityService.getCurrentConnection();
          if (currentConnections.contains(ConnectivityResult.none)) {
            setState(() {
              _consoleLogs.add(
                '>> Erreur: Le téléphone n\'a pas de connexion réseau active.',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Le téléphone n\'a pas de connexion réseau active.',
                  ),
                ),
              );
            });
            return;
          }

          String commandToSend =
              ""; // Variable pour stocker la commande à envoyer
          bool? newState; // État futur de l'appareil (ON/OFF)

          setState(() {
            if (isCustom) {
              final deviceIndex = _customDevices.indexWhere(
                (d) => d['id'] == deviceId,
              );
              if (deviceIndex != -1) {
                newState = !_customDevices[deviceIndex]['state'];
                _customDevices[deviceIndex]['state'] = newState;
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
            _consoleLogs.add(
              '>> Commande locale: $commandToSend',
            ); // Loguer la commande avant l'envoi HTTP
          });

          // Envoyer la commande via HTTP
          final result = await _httpService.sendCommand(
            ip: ip,
            port: port,
            command: commandToSend,
          );

          setState(() {
            if (result.success) {
              _consoleLogs.add('>> Réponse ESP: ${result.message}');
            } else {
              // Si l'envoi a échoué, annuler le changement d'état visuel de l'appareil
              if (isCustom) {
                final deviceIndex = _customDevices.indexWhere(
                  (d) => d['id'] == deviceId,
                );
                if (deviceIndex != -1 && newState != null) {
                  _customDevices[deviceIndex]['state'] =
                      !newState!; // Revenir à l'état précédent
                }
              } else {
                switch (deviceId) {
                  case 1:
                    _led1State = !_led1State;
                    break;
                  case 2:
                    _led2State = !_led2State;
                    break;
                  case 3:
                    _fanState = !_fanState;
                    break;
                  case 4:
                    _tempState = !_tempState;
                    break;
                  case 5:
                    _motorState = !_motorState;
                    break;
                  case 6:
                    _gasState = !_gasState;
                    break;
                }
              }
              _consoleLogs.add('>> Erreur envoi ESP: ${result.message}');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Échec envoi: ${result.message}')),
              );
            }
          });
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
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
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
  // Vérification Wi-Fi
  final List<ConnectivityResult> currentConnections =
      await _connectivityService.getCurrentConnection();
  // Si aucune connexion du tout, alors afficher une erreur générique de réseau
  if (currentConnections.contains(ConnectivityResult.none)) {
    setState(() {
      _consoleLogs.add(
        '>> Erreur: Aucune connexion réseau active sur le téléphone.',
      );
      _wifiConnected = false;
    });
    return;
  }
  // Si le téléphone a une connectivité (même mobile), tentez la connexion à l'ESP.
  // L'ESP est censé être connecté au même réseau (hotspot ou Wi-Fi externe).

  final ip = _ipController.text.trim();
  final port = int.tryParse(_portController.text.trim()) ?? 80;

  // S'il n'y a pas d'IP ou de port valides, ne pas tenter la connexion
  if (ip.isEmpty || port == 0) {
    setState(() {
      _consoleLogs.add(
        '>> Erreur: Veuillez entrer une IP et un port valides.',
      );
      _wifiConnected = false;
    });
    return;
  }

  // Test de connexion direct avec l'ESP
  final result = await _httpService.testConnection(ip: ip, port: port);

  setState(() {
    if (result.success) {
      _wifiConnected = true;
      _consoleLogs.add('>> Connexion établie avec $ip:$port');

      // --- DÉBUT DE LA PARTIE AJOUTÉE POUR LE POLLING CONTINU ---
      _httpService.startPolling(
        ip: ip,
        port: port,
        command: _pollingCommandController.text, // Utilise la commande définie pour le polling
        interval: Duration(seconds: _pollingIntervalSeconds), // Utilise l'intervalle défini
      );
      // --- FIN DE LA PARTIE AJOUTÉE ---

    } else {
      _wifiConnected = false;
      _consoleLogs.add('>> Échec connexion: ${result.message}');
    }
  });
}

  void _sendCommand() async {
    // Ajoutez 'async' car on utilise await
    final command = _commandController.text.trim();
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 80;

    if (ip.isEmpty || port == 0 || command.isEmpty) {
      setState(() {
        _consoleLogs.add('>> Erreur: IP, Port ou Commande invalide.');
      });
      return;
    }

    setState(() {
      _consoleLogs.add('>> Envoi manuel: $command à $ip:$port');
      _commandController.clear();
    });

    // Appel du service HTTP pour envoyer la commande
    final result = await _httpService.sendCommand(
      ip: ip,
      port: port,
      command: command,
    );

    setState(() {
      if (result.success) {
        _consoleLogs.add('>> Réponse: ${result.message}');
      } else {
        _consoleLogs.add('>> Erreur envoi: ${result.message}');
      }
    });
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
                                  _customDevices.add({
                                    'id': DateTime.now().millisecondsSinceEpoch,
                                    'name': deviceName,
                                    'icon': selectedIcon,
                                    'color': selectedColor,
                                    'commandOn': deviceCommandOn,
                                    'commandOff': deviceCommandOff,
                                    'state': false,
                                  });
                                  _consoleLogs.add(
                                    '>> Nouveau capteur ajouté: $deviceName',
                                  );
                                });
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

  void _renameDevice(int deviceId) {
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
            onPressed: () {
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
              }
              Navigator.pop(context);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  void _editDeviceCommands(int deviceId) {
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
            onPressed: () {
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
        _customDevices.removeWhere((d) => d['id'] == deviceId);
        _consoleLogs.add('>> Appareil supprimé');
      });
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
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: 5,
            itemBuilder: (context, index) => ListTile(
              leading: const Icon(Icons.history),
              title: Text('Appareil ${index + 1}'),
              subtitle: Text('10.72.63.${226 + index}:80'),
              trailing: IconButton(
                icon: const Icon(Icons.connect_without_contact),
                onPressed: () =>
                    _connectToHistoryDevice('192.168.1.${100 + index}', '80'),
              ),
            ),
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

  void _connectToHistoryDevice(String ip, String port) {
    setState(() {
      _ipController.text = ip;
      _portController.text = port;
      _wifiConnected = true;
      _consoleLogs.add('>> Connexion historique établie avec $ip:$port');
    });
    Navigator.pop(context);
  }

  void _handleMenuSelection(BuildContext context, String value) {
    switch (value) {
      case 'settings':
        _showAdvancedSettings(context);
        break;
      case 'firebase':
        Navigator.pushNamed(context, '/firebase');
        break;
      case 'help':
        _showHelp(context);
        break;
      case 'about':
        _showAbout(context);
        break;
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
                            hintText: 'Commande manuelle (ex: L1:1)',
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
