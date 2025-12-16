import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:claude_iot/bluetooth/blue_plus.dart' show BluetoothDevice;
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as classic;
import 'package:claude_iot/bluetooth/blue_manager.dart' as manager;
import 'package:claude_iot/utils/data_saver.dart';
import 'package:claude_iot/utils/connect.Persist.dart' as conn_persist;


void main() {
  runApp(const BluetoothApp());
}

class BluetoothApp extends StatelessWidget {
  const BluetoothApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contrôle Bluetooth IoT',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const BluetoothScreen(),
    );
  }
}

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  // Bluetooth Classic par défaut
  manager.BluetoothType _selectedTech = manager.BluetoothType.classic;
  final TextEditingController _commandController = TextEditingController();
  bool _showConsole = false;
  final manager.BluetoothManager _bluetoothManager = manager.BluetoothManager();
  final List<String> _consoleMessages = [];
  final ScrollController _consoleScrollController = ScrollController();
  bool _autoReconnectEnabled = true;
  bool _isReconnecting = false;
  

  List<dynamic> _devices = [];
  final List<dynamic> _knownDevices = [];
  bool _isScanning = false;
  String _scanError = '';
  bool _showDevicesList = false;
  // AJOUTER: Pour gérer les noms personnalisés
  final Map<String, String> _customNames = {};

  // AJOUTER ces méthodes dans _BluetoothScreenState
String _getDeviceName(dynamic device) {
  final deviceId = _getDeviceId(device);
  final customName = _customNames[deviceId];
  
  if (device is BluetoothDevice) {
    return customName ?? device.name ?? 'Appareil inconnu';
  } else if (device is classic.BluetoothDevice) {
    return customName ?? device.name ?? 'Appareil inconnu';
  }
  
  return customName ?? 'Appareil inconnu';
}

String _getDeviceId(dynamic device) {
  if (device is BluetoothDevice) { // Pour BLE
    return device.id;
  } else if (device is classic.BluetoothDevice) { // Pour Classic
    return device.address;
  }
  return device?.id?.toString() ?? device?.address?.toString() ?? '';
}

  // Déclarez la liste des contrôles par défaut comme 'final'
final List<DeviceControl> _defaultControls = [
  DeviceControl(
    name: 'LED1',
    onCommand: 'L1',
    offCommand: 'L0',
    icon: Icons.lightbulb_outline,
    isActive: false,
  ),
  DeviceControl(
    name: 'LED2',
    onCommand: 'L2',
    offCommand: 'L0',
    icon: Icons.lightbulb_outline,
    isActive: false,
  ),
  DeviceControl(
    name: 'Ventilateur',
    onCommand: 'V2',
    offCommand: 'V0',
    icon: Icons.flare,
    isActive: false,
  ),
  DeviceControl(
    name: 'Moteur',
    onCommand: 'M1',
    offCommand: 'M0',
    icon: Icons.electric_meter,
    isActive: false,
  ),
  DeviceControl(
    name: 'Pompe',
    onCommand: 'P1',
    offCommand: 'P0',
    icon: Icons.water_drop,
    isActive: false,
  ),
  DeviceControl(
    name: 'Buzzer',
    onCommand: 'B1',
    offCommand: 'B0',
    icon: Icons.notifications_active,
    isActive: false,
  ),
];

// Déclarez la liste des contrôles de l'UI sans le mot-clé 'final' pour pouvoir la modifier
List<DeviceControl> _controls = [];

final DataSaver _dataSaver = DataSaver();

@override
void initState() {
  super.initState();
  _initializeBluetooth();
  _loadControlsFromDisk();
  _loadConnectionSettings(); // Charger les paramètres de connexion
}


Future<void> _loadControlsFromDisk() async {
  final loadedControls = await _dataSaver.loadControls();
  setState(() {
    if (loadedControls.isNotEmpty) {
      // Créer de nouvelles instances pour éviter les références partagées
      _controls = loadedControls.map((control) => DeviceControl(
        name: control.name,
        onCommand: control.onCommand,
        offCommand: control.offCommand,
        icon: control.icon,
        isActive: false, // ← FORCER à false au démarrage
      )).toList();
    } else {
      // Créer de nouvelles instances à partir des contrôles par défaut
      _controls = _defaultControls.map((control) => DeviceControl(
        name: control.name,
        onCommand: control.onCommand,
        offCommand: control.offCommand,
        icon: control.icon,
        isActive: false, // ← FORCER à false
      )).toList();
      _dataSaver.saveControls(_controls);
    }
  });
}

 Future<void> _loadConnectionSettings() async {
  _autoReconnectEnabled = await conn_persist.ConnectionPersistence.isAutoReconnectEnabled();
  
  // Vérifier s'il y a une connexion sauvegardée et tenter la reconnexion auto
  final savedConnection = await conn_persist.ConnectionPersistence.getSavedConnection();
  if (savedConnection != null && _autoReconnectEnabled) {
    _attemptAutoReconnect(savedConnection);
  }
}

// Tentative de reconnexion automatique
Future<void> _attemptAutoReconnect(Map<String, dynamic> savedConnection) async {
  if (_isReconnecting) return;
  
  setState(() {
    _isReconnecting = true;
  });
  
  try {
    final modeIndex = savedConnection['mode'];
    if (modeIndex == conn_persist.PersistConnectionMode.bluetooth.index) {
      final deviceData = jsonDecode(savedConnection['bluetoothDevice']);
      final persistDevice = conn_persist.PersistBluetoothDevice.fromMap(deviceData);
      final isBle = savedConnection['isBle'] ?? false;
      
      // Définir la technologie
      setState(() {
        _selectedTech = isBle ? manager.BluetoothType.ble : manager.BluetoothType.classic;
      });
      _bluetoothManager.setBluetoothType(_selectedTech);
      
      // Obtenir les appareils appairés
      final bondedDevices = await _bluetoothManager.getBondedDevices();
      
      // Chercher l'appareil sauvegardé dans les appareils appairés
      dynamic deviceToConnect;
      for (var device in bondedDevices) {
        if (_getDeviceId(device) == persistDevice.id) {
          deviceToConnect = device;
          break;
        }
      }
      
      if (deviceToConnect != null) {
        _addConsoleMessage('Tentative de reconnexion automatique à ${persistDevice.name}');
        
        // Attendre que le Bluetooth soit prêt
        await Future.delayed(Duration(seconds: 1));
        
        // Tenter la connexion
        await _bluetoothManager.connectToDevice(deviceToConnect);
        
        // Vérifier si la connexion a réussi
        await Future.delayed(Duration(seconds: 2));
        
        if (_bluetoothManager.connectedDevice != null) {
          _addConsoleMessage('✅ Reconnexion automatique réussie');
          
          // Sauvegarder la nouvelle connexion
          final newPersistDevice = conn_persist.PersistBluetoothDevice(
            id: _getDeviceId(deviceToConnect),
            name: _getDeviceName(deviceToConnect),
            isBle: isBle,
            deviceType: isBle ? 'ble' : 'classic',
          );
          
          await conn_persist.ConnectionPersistence.saveBluetoothConnection(
            device: newPersistDevice,
            isBle: isBle,
          );
        }
      } else {
        _addConsoleMessage('❌ Appareil sauvegardé non trouvé dans les appareils appairés');
      }
    }
  } catch (e) {
    _addConsoleMessage('❌ Échec de la reconnexion automatique: $e');
  } finally {
    setState(() {
      _isReconnecting = false;
    });
  }
}

  @override
  void dispose() {
    _commandController.dispose();
    _bluetoothManager.dispose();
    _consoleScrollController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
  // AJOUT: Vérification des permissions
  final statuses = await [
    Permission.location,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ].request();

  if (statuses.values.any((status) => !status.isGranted)) {
    _addConsoleMessage("Permissions Bluetooth non accordées");
    return;
  }
  setState(() {
    _isScanning = true;
    _scanError = ''; // Réinitialise l'erreur
  });
  await Future.delayed(const Duration(milliseconds: 7000));
  
  try {
    // Vérifier si le Bluetooth est activé
    final isEnabled = await _bluetoothManager.isBluetoothEnabled();
    
    if (!isEnabled) {
      setState(() {
        _scanError = 'Veuillez activer le Bluetooth dans les paramètres';
        _isScanning = false;
      });
      
      // Proposer d'ouvrir les paramètres
      await Future.delayed(Duration(seconds: 2));
      if (!context.mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Bluetooth désactivé'),
          content: const Text('Voulez-vous activer le Bluetooth?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Non'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _bluetoothManager.openBluetoothSettings();
              },
              child: const Text('Oui'),
            ),
          ],
        ),
      );
      
      return;
    }

    // Définir la technologie dans le manager
    _bluetoothManager.setBluetoothType(_selectedTech);
    
    // Démarrer le scan
    _bluetoothManager.scanDevices(10);
    
    // Message de succès dans la console
    _addConsoleMessage(
      'Scan ${_selectedTech == manager.BluetoothType.classic ? 'Classic' : 'BLE'} démarré'
    );
    
  } catch (e) {
    setState(() => _scanError = 'Erreur de scan : ${e.toString()}');
    _addConsoleMessage('ERREUR SCAN: ${e.toString()}');
    
    // Envoyer une notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Échec du scan: ${e.toString()}'),
        backgroundColor: Colors.red,
      )
    );
    
  } finally {
    setState(() => _isScanning = false);
  }
}

Future<void> _stopScan() async {
  try {
    setState(() => _isScanning = false);
    await _bluetoothManager.stopScan();
    _addConsoleMessage('Scan arrêté');
  } catch (e) {
    _addConsoleMessage('Erreur arrêt scan: ${e.toString()}');
    
  }
}

  void _initializeBluetooth() async {
  try {
    await _bluetoothManager.initialize();

    _bluetoothManager.discoveredDevicesStream.listen((devices) {
    setState(() => _devices = devices);
    
    
  });

    // Nouveau: écouter les appareils découverts en temps réel
    _bluetoothManager.discoveredDevicesStream.listen((devices) {
      if (_isScanning) {
        setState(() {
          _devices = devices;
        });
      }
    });

    // Utilisez le receivedDataStream existant pour les données entrantes
    _bluetoothManager.receivedDataStream.listen((data) {
      _addConsoleMessage("<< RECEIVED: $data");
    });

    // Messages généraux du système
    _bluetoothManager.messageStream.listen((message) {
      _addConsoleMessage(message);
    });

    _bluetoothManager.discoveredDevicesStream.listen((devices) {
      setState(() {
        _devices = devices;
        _isScanning = false;
      });
    });
  } catch (e) {
    debugPrint('Erreur initialisation Bluetooth: $e');
    setState(() => _scanError = 'Erreur d\'initialisation Bluetooth : $e');
  }
}

  void _openBluetoothSettings() async {
    try {
      await _bluetoothManager.openBluetoothSettings();
    } on PlatformException catch (e) {
      debugPrint("Failed to open bluetooth settings: '${e.message}'.");
    }
  }


  // REMPLACER la méthode existante
 void _toggleDeviceConnection(dynamic device) async {
  try {
    final currentDevice = _bluetoothManager.connectedDevice;
    final deviceId = _getDeviceId(device);
    
    if (currentDevice != null && (_getDeviceId(currentDevice) == deviceId)) {
      // Déconnexion
      await _bluetoothManager.disconnectDevice();
      
      // Marquer comme déconnecté mais garder l'appareil pour reconnexion auto
      await conn_persist.ConnectionPersistence.markAsDisconnected();
      
      _addConsoleMessage('Déconnecté de ${_getDeviceName(device)}');
    } else {
      // Connexion
      await _bluetoothManager.connectToDevice(device);
      
      // Sauvegarder la connexion pour persistance
      final persistDevice = conn_persist.PersistBluetoothDevice(
        id: deviceId,
        name: _getDeviceName(device),
        isBle: _selectedTech == manager.BluetoothType.ble,
        deviceType: _selectedTech == manager.BluetoothType.ble ? 'ble' : 'classic',
      );
      
      await conn_persist.ConnectionPersistence.saveBluetoothConnection(
        device: persistDevice,
        isBle: _selectedTech == manager.BluetoothType.ble,
      );
      
      if (!_knownDevices.any((d) => _getDeviceId(d) == deviceId)) {
        setState(() => _knownDevices.add(device));
      }
      
      _addConsoleMessage('✅ Connecté à ${_getDeviceName(device)} (connexion persistante activée)');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connecté à ${_getDeviceName(device)}'),
          duration: Duration(seconds: 2),
        )
      );
    }
    setState(() {});
  } catch (e) {
    _addConsoleMessage('❌ Erreur connexion: ${e.toString()}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erreur connexion: ${e.toString()}'))
    );
  }
}

  void _sendCommand(String command) async {
  if (command.isEmpty) return;
  
  if (_bluetoothManager.connectedDevice == null) {
    _addConsoleMessage('Erreur: Aucun appareil connecté');
    return;
  }

  try {
    // Ajoutez un préfixe pour identifier l'envoi
    _addConsoleMessage(">> ENVOI: $command");
    
    await _bluetoothManager.sendCommand(command);
    _commandController.clear();
  } catch (e) {
    _addConsoleMessage('Erreur: $e');
    debugPrint('Erreur envoi commande: $e');
  }
}


void _addConsoleMessage(String message) {
  setState(() {
    _consoleMessages.add(
      '${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second} - $message',
    );
    
    if (_consoleMessages.length > 50) {
      _consoleMessages.removeAt(0);
    }
    
    // Défilement automatique
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_consoleScrollController.hasClients && _showConsole) {
        _consoleScrollController.jumpTo(
          _consoleScrollController.position.maxScrollExtent
        );
      }
    });
  });
}


  // REMPLACER la méthode existante
 Widget _buildDeviceTile(dynamic device) {
  final deviceId = _getDeviceId(device);
  final deviceName = _getDeviceName(device);
  final isConnected = _bluetoothManager.connectedDevice != null && 
      _getDeviceId(_bluetoothManager.connectedDevice) == deviceId;

  return Card(
    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    elevation: isConnected ? 4 : 1,
    shape: RoundedRectangleBorder( // Ajout d'une bordure bleue
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Colors.blue, width: 1),
    ),
    child: ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isConnected ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.bluetooth,
              color: isConnected ? Colors.blue : Colors.grey,
            ),
            if (_selectedTech == manager.BluetoothType.classic)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'C',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      title: Text(
        deviceName,
        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(deviceId),
          Text(
            _selectedTech == manager.BluetoothType.classic ? 'Classic' : 'BLE',
            style: TextStyle(
              color: _selectedTech == manager.BluetoothType.classic 
                  ? Colors.orange 
                  : Colors.blue,
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
        onPressed: () => _toggleDeviceConnection(device),
      ),
    ),
  );
}

// Ajouter cette méthode dans _BluetoothScreenState
Widget _buildReconnectionIndicator() {
  if (_isReconnecting) {
    return Container(
      padding: EdgeInsets.all(8),
      color: Colors.blue[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            'Reconnexion automatique en cours...',
            style: TextStyle(color: Colors.blue[800], fontSize: 12),
          ),
        ],
      ),
    );
  }
  return SizedBox.shrink();
}

// Modifier le widget _buildTechSelector comme ceci
Widget _buildTechSelector() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.blue), // Bordure bleue
    ),
    child: DropdownButton<manager.BluetoothType>(
      value: _selectedTech,
      underline: const SizedBox(),
      icon: const Icon(Icons.bluetooth),
      items: [
        DropdownMenuItem(
          value: manager.BluetoothType.classic,
          child: Row(
            children: [
              Icon(Icons.settings_remote, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text('Classic', style: GoogleFonts.inter()),
            ],
          ),
        ),
        DropdownMenuItem(
          value: manager.BluetoothType.ble,
          child: Row(
            children: [
              Icon(Icons.bluetooth_audio, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Text('BLE', style: GoogleFonts.inter()),
            ],
          ),
        ),
      ],
      onChanged: (manager.BluetoothType? value) {
        if (value != null) {
          setState(() => _selectedTech = value);
        }
      },
    ),
  );
}  

Widget _buildConsoleSection() {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    height: _showConsole ? MediaQuery.of(context).size.height * 0.25 : 36,
    curve: Curves.easeInOut,
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color: _showConsole ? const Color(0xFFEDF4FF) : Colors.grey[200],
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.blue, width: 2),
      boxShadow: [
        BoxShadow(
          color: Colors.blue.withOpacity(0.08),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: _showConsole 
        ? Column(
            children: [
              // Header avec hauteur fixe
              SizedBox(
                height: 36,
                child: GestureDetector(
                  onTap: () => setState(() => _showConsole = !_showConsole),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Console',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                        Icon(
                          _showConsole ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                          color: Colors.blue[800],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Contenu principal avec Expanded pour prendre l'espace restant
              Expanded(
                child: Container(
                  color: const Color(0xFFEDF4FF),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    children: [
                      // Liste des messages avec Expanded
                      Expanded(
                        child: ListView.builder(
                          controller: _consoleScrollController,
                          itemCount: _consoleMessages.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                _consoleMessages[index],
                                style: GoogleFonts.robotoMono(fontSize: 12),
                              ),
                            );
                          },
                        ),
                      ),
                      
                      // Champ de commande en bas (hauteur fixe)
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
                                  borderSide: BorderSide(color: Colors.blue),
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.send, size: 20),
                            label: const Text('Envoyer'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            ),
                            onPressed: () => _sendCommand(_commandController.text),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )
        : 
        // Version réduite de la console
        GestureDetector(
            onTap: () => setState(() => _showConsole = !_showConsole),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.code, color: Colors.blue, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Console',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
  );
}


  // Section contrôles inchangée
Widget _buildControlsSection() {
  return Expanded(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Contrôles',
                style: GoogleFonts.interTight(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: _showAddControlDialog,
                  tooltip: 'Ajouter un contrôle',
                ),
              ),
            ],
          ),
        ),
        // Nouveau conteneur avec bordure bleue
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                childAspectRatio: 0.8,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _controls.length,
              itemBuilder: (context, index) => _buildControlCard(_controls[index]),
            ),
          ),
        ),
      ],
    ),
  );
}

// Carte de contrôle modifiée
 // Carte de contrôle modifiée avec vérification de connexion
Widget _buildControlCard(DeviceControl control) {
  return GestureDetector(
    onTap: () {
      // Vérifier si un appareil est connecté
      if (_bluetoothManager.connectedDevice == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Aucun appareil connecté. Veuillez vous connecter à un appareil.'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      setState(() {
        control.isActive = !control.isActive;
        final command = control.isActive ? control.onCommand : control.offCommand;
        _sendCommand(command);
      });
    },
    child: Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: control.isActive ? Colors.blue : Colors.grey,
          width: 2,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(Icons.more_vert, size: 16),
              onPressed: () => _showControlOptions(control),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  control.icon,
                  size: 48,
                  color: control.isActive ? Colors.amber : Colors.grey,
                ),
                const SizedBox(height: 8),
                Text(
                  control.name,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: control.isActive ? Colors.black : Colors.grey,
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

  // REMPLACER la méthode existante
Widget _buildDevicesSection() {
  return Card(
    margin: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 4,
    color: _isScanning
        ? const Color.fromARGB(255, 200, 191, 247)
        : const Color.fromARGB(255, 218, 233, 185),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section appareil connecté - toujours visible
          if (_bluetoothManager.connectedDevice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bluetooth_connected, 
                          color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Connecté à:',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _showDevicesList ? Icons.expand_less : Icons.expand_more,
                          color: Colors.blue[800],
                        ),
                        tooltip: _showDevicesList
                            ? 'Masquer la section scan'
                            : 'Afficher la section scan',
                        onPressed: () {
                          setState(() => _showDevicesList = !_showDevicesList);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getDeviceName(_bluetoothManager.connectedDevice!),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    _getDeviceId(_bluetoothManager.connectedDevice!),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),

          // Section scan et appareils - masquée par défaut après connexion
          if ((_bluetoothManager.connectedDevice == null) || _showDevicesList) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appareils Bluetooth',
                  style: GoogleFonts.interTight(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Technologie sélectionnée: ${_selectedTech == manager.BluetoothType.classic ? 'Classic' : 'BLE'}',
                  style: GoogleFonts.inter(
                    color: _selectedTech == manager.BluetoothType.classic 
                        ? Colors.orange 
                        : Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Boutons et indicateurs
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTechSelector(),
                if (_bluetoothManager.connectedDevice == null) // Visible uniquement quand déconnecté
                  IconButton(
                    icon: Icon(
                      _showDevicesList ? Icons.expand_less : Icons.expand_more,
                      color: Colors.blue[800],
                    ),
                    tooltip: _showDevicesList
                        ? 'Masquer la liste'
                        : 'Afficher la liste',
                    onPressed: () {
                      setState(() => _showDevicesList = !_showDevicesList);
                    },
                  ),
                _isScanning
                    ? ElevatedButton.icon(
                        onPressed: _stopScan,
                        icon: const Icon(Icons.stop, size: 20),
                        label: const Text('Arrêter'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: _startScan,
                        icon: Icon(
                          _selectedTech == manager.BluetoothType.classic 
                              ? Icons.settings_remote
                              : Icons.bluetooth,
                          size: 20,
                        ),
                        label: const Text('Scanner'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedTech == manager.BluetoothType.classic 
                              ? Colors.orange 
                              : Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                      ),
              ],
            ),

            // Indicateur de scan
            if (_isScanning)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Recherche en cours...',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
              ),

            if (_scanError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Text(
                  _scanError,
                  style: GoogleFonts.inter(
                    color: Colors.red, 
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            
            // Liste des appareils
            if (_showDevicesList)
              Container(
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.3,
                ),
                child: _isScanning && _devices.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      )
                    : _devices.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('Aucun appareil trouvé'),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _devices.length,
                            itemBuilder: (context, index) => 
                                _buildDeviceTile(_devices[index]),
                          ),
              ),
          ],
        ],
      ),
    ),
  );
}
  void _showAddControlDialog() {
  showDialog(
    context: context,
    builder: (context) => AddControlDialog(
      onAdd: (control) {
        setState(() {
          // Toujours ajouter avec isActive: false
          _controls.add(DeviceControl(
            name: control.name,
            onCommand: control.onCommand,
            offCommand: control.offCommand,
            icon: control.icon,
            isActive: false,
          ));
        });
        _dataSaver.saveControls(_controls);
      },
    ),
  );
}

  void _showControlOptions(DeviceControl control) {
  showModalBottomSheet(
    context: context,
    builder: (context) => ControlOptionsSheet(
      control: control,
      onUpdate: (updatedControl) {
        setState(() {
          final index = _controls.indexOf(control);
          if (index != -1) {
            // Créer une nouvelle instance pour éviter les problèmes de référence
            _controls[index] = DeviceControl(
              name: updatedControl.name,
              onCommand: updatedControl.onCommand,
              offCommand: updatedControl.offCommand,
              icon: updatedControl.icon,
              isActive: _controls[index].isActive, // Garder l'état actuel
            );
          }
        });
        _dataSaver.saveControls(_controls);
      },
      onDelete: () {
        setState(() {
          _controls.remove(control);
        });
        _dataSaver.saveControls(_controls);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${control.name} supprimé')),
        );
      },
    ),
  );
}
  void _showAdvancedSettings() {
  showModalBottomSheet(
    context: context,
    builder: (context) => Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.bluetooth),
            title: Text('Paramètres avancés'),
            onTap: () {
              _openBluetoothSettings();
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.autorenew),
            title: Text('Reconnexion automatique'),
            onTap: () {
              Navigator.pop(context);
              _showAutoReconnectDialog();
            },
          ),
          ListTile(
            leading: Icon(Icons.settings),
            title: Text('Configuration des contrôles'),
            onTap: () {
              Navigator.pop(context);
              _showAllControlsConfiguration();
            },
          ),
          ListTile(
            leading: Icon(Icons.help),
            title: Text('Aide'),
            onTap: () {
              Navigator.pop(context);
              _showHelpDialog();
            },
          ),
          ListTile(
            leading: Icon(Icons.info),
            title: Text('À propos'),
            onTap: () {
              Navigator.pop(context);
              _showAboutDialog();
            },
          ),
        ],
      ),
    ),
  );
}

  void _showAllControlsConfiguration() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configuration des contrôles'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _controls.length,
            itemBuilder: (context, index) {
              final control = _controls[index];
              return ListTile(
                title: Text(control.name),
                subtitle: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('ON: ${control.onCommand}'),
    Text('OFF: ${control.offCommand}'),
  ],
),
                leading: Icon(control.icon),
                trailing: Switch(
                  value: control.isActive,
                  onChanged: (value) {
                    setState(() {
                      control.isActive = value;
                    });
                  },
                ),
              );
            },
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

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aide'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Bienvenue dans l\'application de contrôle Bluetooth IoT.\n\n'
                'Pour commencer :\n'
                '1. Appuyez sur le bouton Scanner pour rechercher les appareils à proximité\n'
                '2. Sélectionnez un appareil dans la liste pour vous connecter\n'
                '3. Utilisez les boutons de contrôle pour envoyer des commandes\n\n'
                'Format des commandes : [Appareil][Numéro]:[Valeur]\n'
                'Exemple : L1 pour allumer la LED 1',
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // Lien vers la documentation
                },
                child: const Text('Voir la documentation complète'),
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

  void _showKnownDevicesDialog() async {
  List<dynamic> bondedDevices = await _bluetoothManager.getBondedDevices();

  showDialog(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Appareils connus',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Section: Appareils de l'application
            const Text(
              'Appareils enregistrés',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _knownDevices.length,
                itemBuilder: (context, index) => 
                    _buildKnownDeviceTile(_knownDevices[index]),
              ),
            ),

            const SizedBox(height: 16),
            
            // Section: Appareils du téléphone
            const Text(
              'Appareils appairés',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: bondedDevices.length,
                itemBuilder: (context, index) => 
                    _buildKnownDeviceTile(bondedDevices[index]),
              ),
            ),
            
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('Fermer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildKnownDeviceTile(dynamic device) {
  final isConnected = _bluetoothManager.connectedDevice != null && 
      _getDeviceId(_bluetoothManager.connectedDevice) == _getDeviceId(device);

  return Card(
    margin: const EdgeInsets.symmetric(vertical: 4),
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    child: ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isConnected ? Colors.blue[50] : Colors.grey[200],
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.bluetooth,
          color: isConnected ? Colors.blue : Colors.grey,
        ),
      ),
      title: Text(
        _getDeviceName(device),
        style: GoogleFonts.inter(
          fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
          color: isConnected ? Colors.blue : Colors.black87,
        ),
      ),
      subtitle: Text(
        _getDeviceId(device),
        style: GoogleFonts.inter(fontSize: 12),
      ),
      trailing: IconButton(
        icon: Icon(
          isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
          color: isConnected ? Colors.blue : Colors.grey,
        ),
        onPressed: () {
          Navigator.pop(context);
          _toggleDeviceConnection(device);
        },
      ),
    ),
  );
}

  void _showDeviceOptionsDialog(dynamic device) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Renommer'),
            onTap: () {
              Navigator.pop(context);
              _showRenameDeviceDialog(device);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Supprimer', style: TextStyle(color: Colors.red)),
            onTap: () {
              setState(() {
                _knownDevices.removeWhere((d) => d.id == device.id);
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // REMPLACER la méthode existante
void _showRenameDeviceDialog(dynamic device) {
  final deviceId = _getDeviceId(device);
  final controller = TextEditingController(
    text: _customNames[deviceId] ?? _getDeviceName(device)
  );
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Renommer l\'appareil'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Nom'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () {
            setState(() => _customNames[deviceId] = controller.text);
            Navigator.pop(context);
          },
          child: const Text('Renommer'),
        ),
      ],
    ),
  );
}

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Contrôle IoT Bluetooth',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(
        Icons.bluetooth,
        size: 50,
        color: Colors.blue,
      ),
      children: const [
        SizedBox(height: 20),
        Text('Application de contrôle d\'appareils IoT via Bluetooth'),
        SizedBox(height: 10),
        Text('Développé avec Flutter'),
      ],
    );
  }

  // Dans la classe _BluetoothScreenState, après _showAboutDialog()
void _showAutoReconnectDialog() {
  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Reconnexion automatique'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('La reconnexion automatique permet de se reconnecter au dernier appareil connecté au démarrage de l\'application.'),
            SizedBox(height: 16),
            Row(
              children: [
                Switch(
                  value: _autoReconnectEnabled,
                  onChanged: (value) async {
                    setState(() {
                      _autoReconnectEnabled = value;
                    });
                    await conn_persist.ConnectionPersistence.setAutoReconnect(value);
                  },
                ),
                SizedBox(width: 8),
                Text('Reconnexion automatique'),
              ],
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
    ),
  );
}

  
  @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Contrôle Bluetooth IoT'),
      backgroundColor: const Color.fromARGB(255, 80, 224, 243),
      actions: [
  // Icône d'état Bluetooth
  FutureBuilder<bool>(
    future: _bluetoothManager.isBluetoothEnabled(),
    builder: (context, snapshot) {
      final isEnabled = snapshot.data ?? false;
      return Icon(
        isEnabled ? Icons.bluetooth : Icons.bluetooth_disabled,
        color: isEnabled ? const Color.fromARGB(255, 21, 5, 238) : const Color.fromARGB(255, 240, 69, 69),
      );
    },
  ),
  const SizedBox(width: 10),
  IconButton(
    icon: const Icon(Icons.computer),
    tooltip: 'Appareils connus',
    onPressed: _showKnownDevicesDialog,
  ),
  IconButton(
    icon: const Icon(Icons.settings),
    onPressed: _showAdvancedSettings,
    tooltip: 'Paramètres',
  ),
],
    ),
      body: Column(
        children: [
          _buildReconnectionIndicator(),
          _buildDevicesSection(),
          _buildControlsSection(),
          _buildConsoleSection(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startScan,
        tooltip: 'Scanner',
        child: const Icon(Icons.search),
      ),
    );
  }
}

class DeviceControl {
  final String name;
  final String onCommand;  // Commande pour allumer
  final String offCommand; // Commande pour éteindre
  final IconData icon;
  bool isActive;           // État actuel

  DeviceControl({
    required this.name,
    required this.onCommand,
    required this.offCommand,
    required this.icon,
    this.isActive = false, // Par défaut éteint
  });
}

class AddControlDialog extends StatefulWidget {
  final Function(DeviceControl) onAdd;

  const AddControlDialog({super.key, required this.onAdd});

  @override
  State<AddControlDialog> createState() => _AddControlDialogState();
}

class _AddControlDialogState extends State<AddControlDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _onCommandController = TextEditingController();
  final _offCommandController = TextEditingController();
  IconData _selectedIcon = Icons.device_unknown;

  @override
  void dispose() {
    _nameController.dispose();
    _onCommandController.dispose();
    _offCommandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un contrôle'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nom du contrôle'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer un nom';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _onCommandController,
                decoration: const InputDecoration(
                  labelText: 'Commande ON',
                  hintText: 'Ex: L1',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer une commande ON';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _offCommandController,
                decoration: const InputDecoration(
                  labelText: 'Commande OFF',
                  hintText: 'Ex: L1:0',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer une commande OFF';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text('Icône :'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildIconButton(Icons.lightbulb_outline, 'Ampoule'),
                  _buildIconButton(Icons.flare, 'Ventilateur'),
                  _buildIconButton(Icons.electric_meter, 'Moteur'),
                  _buildIconButton(Icons.water_drop, 'Pompe'),
                  _buildIconButton(Icons.notifications_active, 'Buzzer'),
                  _buildIconButton(Icons.device_unknown, 'Autre'),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              widget.onAdd(
                DeviceControl(
                  name: _nameController.text,
                  onCommand: _onCommandController.text,
                  offCommand: _offCommandController.text,
                  icon: _selectedIcon,
                  isActive: false,
                ),
              );
              Navigator.pop(context);
            }
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }

  Widget _buildIconButton(IconData icon, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon),
        color: _selectedIcon == icon
            ? Theme.of(context).primaryColor
            : Colors.grey,
        onPressed: () {
          setState(() {
            _selectedIcon = icon;
          });
        },
      ),
    );
  }
}

class ControlOptionsSheet extends StatelessWidget {
  final DeviceControl control;
  final Function(DeviceControl) onUpdate;
  final VoidCallback onDelete;

  const ControlOptionsSheet({
    super.key,
    required this.control,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Modifier'),
            onTap: () {
              Navigator.pop(context);
              _showEditDialog(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Supprimer', style: TextStyle(color: Colors.red)),
            onTap: () {
              onDelete();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // REMPLACER toute la méthode _showEditDialog (ligne ~1100)
void _showEditDialog(BuildContext context) {
  final nameController = TextEditingController(text: control.name);
  // AJOUTER deux contrôleurs pour ON/OFF
  final onCommandController = TextEditingController(text: control.onCommand);
  final offCommandController = TextEditingController(text: control.offCommand);
  IconData selectedIcon = control.icon;

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Modifier le contrôle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom du contrôle',
                  ),
                ),
                const SizedBox(height: 16),
                // AJOUTER champ commande ON
                TextFormField(
                  controller: onCommandController,
                  decoration: const InputDecoration(
                    labelText: 'Commande ON',
                  ),
                ),
                const SizedBox(height: 16),
                // AJOUTER champ commande OFF
                TextFormField(
                  controller: offCommandController,
                  decoration: const InputDecoration(
                    labelText: 'Commande OFF',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Icône :'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildIconButton(
                      context,
                      Icons.lightbulb_outline,
                      selectedIcon,
                      () => setState(() => selectedIcon = Icons.lightbulb_outline),
                    ),
                    _buildIconButton(
                      context,
                      Icons.flare,
                      selectedIcon,
                      () => setState(() => selectedIcon = Icons.flare),
                    ),
                    _buildIconButton(
                      context,
                      Icons.electric_meter,
                      selectedIcon,
                      () => setState(() => selectedIcon = Icons.electric_meter),
                    ),
                    _buildIconButton(
                      context,
                      Icons.water_drop,
                      selectedIcon,
                      () => setState(() => selectedIcon = Icons.water_drop),
                    ),
                    _buildIconButton(
                      context,
                      Icons.notifications_active,
                      selectedIcon,
                      () => setState(() => selectedIcon = Icons.notifications_active),
                    ),
                    _buildIconButton(
                      context,
                      Icons.device_unknown,
                      selectedIcon,
                      () => setState(() => selectedIcon = Icons.device_unknown),
                    ),
                  ],
                  
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
                onUpdate(
                  DeviceControl(
                    name: nameController.text,
                    // UTILISER les nouvelles commandes
                    onCommand: onCommandController.text,
                    offCommand: offCommandController.text,
                    icon: selectedIcon,
                    isActive: control.isActive,
                  ),
                );
                
                Navigator.pop(context); 
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      );
    },
  );
}

  Widget _buildIconButton(
    BuildContext context,
    IconData icon,
    IconData selectedIcon,
    VoidCallback onPressed,
  ) {
    return IconButton(
      icon: Icon(icon),
      color: selectedIcon == icon
          ? Theme.of(context).primaryColor
          : Colors.grey,
      onPressed: onPressed,
      tooltip: icon.toString(),
    );
  }
}