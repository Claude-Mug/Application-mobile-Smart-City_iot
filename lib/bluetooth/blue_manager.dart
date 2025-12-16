import 'dart:async';
import 'dart:typed_data'; // Nécessaire pour Uint8List
import 'package:flutter/services.dart';
import 'blue_classic.dart'; // Gestionnaire Bluetooth Classic
import 'blue_plus.dart';   // Gestionnaire BLE
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as classic; // Correction de l'import

/// Types de connexion Bluetooth supportés
enum BluetoothType { ble, classic }

/// Classe centralisée pour gérer BLE et Bluetooth Classic
class BluetoothManager {
  // 
  BluetoothType _currentType = BluetoothType.classic;
  final BluetoothBluePlus _bluePlus = BluetoothBluePlus();
  final BluetoothClassicManager _classicManager = BluetoothClassicManager();

  // Configuration
  int _scanDuration = 10;

  // Streams pour l'UI
  final _devicesController = StreamController<List<dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _messageController = StreamController<String>.broadcast();
  final _receivedDataController = StreamController<String>.broadcast();
  StreamSubscription? _scanSubscription;

  // Getters
  Stream<List<dynamic>> get discoveredDevicesStream => _devicesController.stream;
  Stream<bool> get connectionStateStream => _connectionController.stream;
  Stream<String> get messageStream => _messageController.stream;
  Stream<String> get receivedDataStream => _receivedDataController.stream;
  
  BluetoothType get bluetoothType => _currentType;
  int get scanDuration => _scanDuration;

  // Setters
  void setBluetoothType(BluetoothType type) => _currentType = type;
  void setScanDuration(int value) => _scanDuration = value.clamp(5, 60);

  // Appareil connecté
  dynamic _connectedDevice;
  dynamic get connectedDevice => _connectedDevice;

  // UUIDs BLE (non utilisés en Classic)
  String? _serviceUuid;
  String? _characteristicUuid;

  // Souscriptions
  StreamSubscription? _dataSubscription;
 
  BluetoothManager() {
    // Écouter les appareils BLE
    _bluePlus.discoveredDevicesStream.listen((devices) {
      if (_currentType == BluetoothType.ble) {
        _devicesController.add(devices);
      }
    });

    // Écouter les appareils Classic
    _classicManager.discoveredDevicesStream.listen((devices) {
      if (_currentType == BluetoothType.classic) {
        _devicesController.add(devices);
      }
    });
  }

  /// Initialise les gestionnaires Bluetooth
  // blue_manager.dart
Future<void> initialize() async {
  try {
    // Vérifie si le Bluetooth est activé
    final isEnabled = await isBluetoothEnabled();
    if (!isEnabled) {
      throw Exception('Bluetooth désactivé');
    }
    
    // Initialise le BLE
    await _bluePlus.initialize();
  } catch (e) {
    _messageController.add('Initialisation Bluetooth échouée: $e');
  }
}

  /// Ouvre les paramètres Bluetooth natifs
  Future<void> openBluetoothSettings() async {
  try {
    await MethodChannel('flutter.native/helper')
        .invokeMethod('openBluetoothSettings');
    _messageController.add('Paramètres Bluetooth ouverts');
  } on PlatformException catch (e) {
    _messageController.add('Erreur ouverture paramètres: ${e.message}');
  }
}
  /// Connexion à un appareil
  Future<void> connectToDevice(dynamic device) async {
    try {
      // Annule toute souscription précédente
      await _dataSubscription?.cancel();
      _dataSubscription = null;

      if (_currentType == BluetoothType.ble) {
        // Connexion BLE
        await _bluePlus.connect(device.id);
        _connectedDevice = device;
        
        // Découverte des services (BLE seulement)
        final discovered = await _bluePlus.discoverServicesAndCharacteristics(device.id);
        _serviceUuid = discovered['serviceUuid']?.toString();
        _characteristicUuid = discovered['characteristicUuid']?.toString();
        
        // Écoute des données BLE
        if (_bluePlus.receivedDataStream != null) {
          _dataSubscription = _bluePlus.receivedDataStream!.listen((data) {
            _receivedDataController.add(data);
          });
        }
      } else {
        // Connexion Classic
        await _classicManager.connect(device);
        _connectedDevice = device;
        
        // Écoute des données Classic
        _dataSubscription = _classicManager.dataStream.listen((data) {
          _receivedDataController.add(data);
        });
      }
      
      _connectionController.add(true);
      _messageController.add('Connecté à ${device.name}');
    } catch (e) {
      _messageController.add('Échec connexion: ${e.toString()}');
      _connectionController.add(false);
    }
  }

  /// Déconnexion de l'appareil
  Future<void> disconnectDevice() async {
    try {
      await _dataSubscription?.cancel();
      _dataSubscription = null;

      if (_currentType == BluetoothType.ble) {
        await _bluePlus.disconnect();
      } else {
        await _classicManager.disconnect();
      }
      
      _messageController.add('Déconnecté de ${_connectedDevice?.name}');
      _connectedDevice = null;
      _connectionController.add(false);
    } catch (e) {
      _messageController.add('Erreur déconnexion: ${e.toString()}');
    }
  }

  /// Envoi de commande à l'appareil
  Future<void> sendCommand(String command) async {
    if (_connectedDevice == null) {
      _messageController.add('Aucun appareil connecté');
      return;
    }

    try {
      if (_currentType == BluetoothType.ble) {
        // Envoi via caractéristique BLE
        await _bluePlus.sendCommandToUuid(
          command,
          serviceUuid: _serviceUuid!,
          characteristicUuid: _characteristicUuid!,
        );
      } else {
        // Envoi direct en Classic
        await _classicManager.sendData(command);
      }
      _messageController.add('Commande envoyée: $command');
    } catch (e) {
      _messageController.add('Erreur envoi: ${e.toString()}');
    }
  }

  // Dans blue_manager.dart

/// Vérifie si le Bluetooth est activé
Future<bool> isBluetoothEnabled() async {
  try {
    if (_currentType == BluetoothType.ble) {
      return await _bluePlus.isBluetoothEnabled();
    } else {
      return await _classicManager.isBluetoothEnabled();
    }
  } catch (e) {
    _messageController.add('Erreur vérification Bluetooth: ${e.toString()}');
    return false;
  }
}

// Remplacer toute la méthode startScan() dans BluetoothManager
// blue_manager.dart
Future<void> startScan() async {
  _devicesController.add([]);
  _messageController.add('Démarrage du scan ${_currentType == BluetoothType.classic ? "Classic" : "BLE"}');
  
  try {
    if (_currentType == BluetoothType.ble) {
      // Nouvelle méthode avec mise à jour en temps réel
      await _bluePlus.scanDevices(_scanDuration);
    } else {
      _classicManager.scanDevices(timeout: Duration(seconds: _scanDuration));
    }
  } catch (e) {
    _messageController.add('Erreur scan: ${e.toString()}');
    rethrow;
  }
}


/// Récupère les appareils appairés
Future<List<dynamic>> getBondedDevices() async {
  if (_currentType == BluetoothType.classic) {
    return await _classicManager.getBondedDevices();
  } else {
    return []; // BLE ne gère pas les appareils appairés de la même façon
  }
}

Future<void> stopScan() async {
  try {
    if (_currentType == BluetoothType.ble) {
      await _bluePlus.stopScan();
    } else {
      await _classicManager.stopScan();
    }
    _messageController.add('Scan arrêté');
  } catch (e) {
    _messageController.add('Erreur arrêt scan: ${e.toString()}');
  }
}
  /// Envoi de données binaires (Classic seulement)
  Future<void> sendBytes(Uint8List data) async {
    if (_currentType != BluetoothType.classic) {
      _messageController.add('Envoi binaire supporté en Classic seulement');
      return;
    }

    try {
      await _classicManager.sendBytes(data);
      _messageController.add('Données binaires envoyées (${data.length} octets)');
    } catch (e) {
      _messageController.add('Erreur envoi binaire: ${e.toString()}');
    }
  }

  Future<void> scanDevices(int duration) async {
  _scanDuration = duration; // Mettre à jour la durée
  _devicesController.add([]); // Réinitialise la liste
  _messageController.add(
    'Démarrage du scan ${_currentType == BluetoothType.classic ? "Classic" : "BLE"}'
  );
  
  try {
    if (_currentType == BluetoothType.ble) {
      final devices = await _bluePlus.scanDevices(_scanDuration);
      _devicesController.add(devices);
    } else {
      final devices = await _classicManager.scanDevices(
        timeout: Duration(seconds: _scanDuration),
      );
      _devicesController.add(devices);
    }
  } catch (e) {
    _messageController.add('Erreur scan: ${e.toString()}');
    rethrow;
  }
}

 

  /// Appairage (Classic Android seulement)
  Future<void> bondDevice(dynamic device) async {
    if (_currentType != BluetoothType.classic) return;
    
    try {
      // Utilisation de l'alias pour le cast
      await _classicManager.bondDevice(device as classic.BluetoothDevice);
      _messageController.add('Appareil appairé: ${device.name}');
    } catch (e) {
      _messageController.add('Échec appairage: ${e.toString()}');
    }
  }

  /// Nettoyage des ressources
  void dispose() {
    _dataSubscription?.cancel();
    _bluePlus.dispose();
    _classicManager.dispose();
    _devicesController.close();
    _connectionController.close();
    _messageController.close();
    _receivedDataController.close();
  }
}