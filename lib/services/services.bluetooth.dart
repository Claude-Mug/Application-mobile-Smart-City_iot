import 'dart:async';
import 'package:claude_iot/bluetooth/commun/bluetooth_classic.dart';
import 'package:claude_iot/bluetooth/commun/bluetooth_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp; // Pour l'état de connexion BLE

enum BluetoothProtocol {
  classic,
  ble,
  none, // Pour indiquer qu'aucun protocole spécifique n'est actif
}

class BluetoothCommunicationManager {
  final BluetoothClassicManager _classicManager = BluetoothClassicManager();
  final BluetoothBluePlus _bleManager = BluetoothBluePlus();

  BluetoothProtocol _activeProtocol = BluetoothProtocol.none;

  // --- Flux pour les appareils découverts (combinés) ---
  final StreamController<List<BluetoothDevice>> _discoveredDevicesController = StreamController<List<BluetoothDevice>>.broadcast();
  Stream<List<BluetoothDevice>> get discoveredDevicesStream => _discoveredDevicesController.stream;

  // --- Flux pour les données reçues (combinés) ---
  final StreamController<String> _receivedDataController = StreamController<String>.broadcast();
  Stream<String> get receivedDataStream => _receivedDataController.stream;

  // --- Flux pour l'état de connexion global (combiné) ---
  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  // --- Flux pour l'état global du Bluetooth (activé/désactivé) ---
  final StreamController<bool> _bluetoothEnabledController = StreamController<bool>.broadcast();
  Stream<bool> get bluetoothEnabledStream => _bluetoothEnabledController.stream;


  // Initialisation du gestionnaire Bluetooth
  Future<void> initialize() async {
    try {
      await _bleManager.initialize();
      _bluetoothEnabledController.add(await isBluetoothEnabled()); // État initial
    } catch (e) {
      print('Erreur lors de l\'initialisation des managers Bluetooth: $e');
      _bluetoothEnabledController.add(false);
    }

    // Écoute des appareils découverts des deux managers (qui émettent maintenant le modèle commun)
    _classicManager.discoveredDevicesStream.listen((classicDevices) {
      _discoveredDevicesController.add(classicDevices);
    });
    _bleManager.discoveredDevicesStream.listen((bleDevices) {
      _discoveredDevicesController.add(bleDevices);
    });

    // Écoute des données reçues des deux managers
    _classicManager.dataStream.listen((data) {
      _receivedDataController.add('[CLASSIC] $data');
    });
    _bleManager.receivedDataStream?.listen((data) {
      _receivedDataController.add('[BLE] $data');
    });

    // Écoute de l'état de connexion des deux managers
    _classicManager.connectionStateStream.listen((isConnected) {
      _connectionStateController.add(isConnected);
    });
    // Pour BLE, nous écoutons l'état du périphérique connecté.
    // Note : _bleManager.connectedDevice doit être mis à jour lorsque la connexion BLE est établie/perdue.
    // L'état de connexion de FlutterBluePlus est fbp.BluetoothConnectionState
    _bleManager.connectedDevice?.connectionState.listen((state) {
        _connectionStateController.add(state == fbp.BluetoothConnectionState.connected); 
    });
  }

  bool isConnected() {
    if (_activeProtocol == BluetoothProtocol.classic) {
      return _classicManager.isConnected;
    } else if (_activeProtocol == BluetoothProtocol.ble) {
      return _bleManager.connectedDevice != null;
    }
    return false;
  }

  // Vérifie si le Bluetooth est activé (prend en compte les deux types si possible)
  Future<bool> isBluetoothEnabled() async {
    final bool classicEnabled = await _classicManager.isBluetoothEnabled();
    final bool bleEnabled = await _bleManager.isBluetoothEnabled();
    return classicEnabled || bleEnabled; // Vrai si au moins l'un des deux est activé
  }

  // Active/Désactive le Bluetooth (via Classic car BLE n'a pas cette capacité directe)
  Future<void> setBluetoothEnabled(bool enable) async {
    await _classicManager.setEnable(enable);
    _bluetoothEnabledController.add(enable);
  }


  void setActiveProtocol(BluetoothProtocol protocol) {
    _activeProtocol = protocol;
    print('BluetoothCommunicationManager: Protocole actif défini sur: $_activeProtocol.');
  }

  BluetoothProtocol getActiveProtocol() => _activeProtocol;

  /// Lance un scan pour les appareils Bluetooth (Classic ou BLE selon le protocole actif)
  /// Retourne une liste d'appareils découverts.
  /// [duration] : Durée du scan en secondes.
  Future<List<BluetoothDevice>> scanDevices({
    required BluetoothProtocol protocol,
    int duration = 10,
    bool pairedOnly = false, // Uniquement pour Classic
  }) async {
    setActiveProtocol(protocol); // Définit le protocole actif pour les opérations futures

    if (protocol == BluetoothProtocol.classic) {
      return await _classicManager.scanDevices(timeout: Duration(seconds: duration), pairedOnly: pairedOnly);
    } else if (protocol == BluetoothProtocol.ble) {
      return await _bleManager.scanDevices(duration);
    } else {
      throw Exception('Protocole de scan Bluetooth non valide ou non spécifié.');
    }
  }

  /// Arrête le scan en cours pour le protocole actif.
  Future<void> stopScan() async {
    if (_activeProtocol == BluetoothProtocol.classic) {
      await _classicManager.stopScan();
    } else if (_activeProtocol == BluetoothProtocol.ble) {
      await _bleManager.stopScan();
    }
    print('BluetoothCommunicationManager: Scan arrêté pour le protocole $_activeProtocol.');
  }

  /// Tente de se connecter à un appareil Bluetooth.
  /// [device] : L'appareil Bluetooth à connecter.
  Future<void> connectToDevice(BluetoothDevice device) async {
    if (device.isBle) {
      setActiveProtocol(BluetoothProtocol.ble);
      await _bleManager.connect(device.id);
      // Mise à jour de l'état de connexion après une connexion BLE réussie
      _connectionStateController.add(true);
      // Écouter les services et caractéristiques pour BLE dès la connexion
      try {
        final bleUuids = await _bleManager.discoverServicesAndCharacteristics(device.id);
        print('Services/Caractéristiques BLE découverts: $bleUuids');
        // Vous pouvez stocker ces UUIDs si vous en avez besoin plus tard pour sendCommand
      } catch (e) {
        print('Erreur découverte services/caractéristiques BLE: $e');
        // Ne pas lancer l'erreur, la connexion est peut-être quand même établie
      }
    } else {
      setActiveProtocol(BluetoothProtocol.classic);
      await _classicManager.connect(device); // Passe directement votre modèle commun
      // Mise à jour de l'état de connexion après une connexion Classic réussie
      _connectionStateController.add(true);
    }
    print('BluetoothCommunicationManager: Connecté à ${device.name} via $_activeProtocol.');
  }

  /// Déconnecte l'appareil actuellement connecté.
  Future<void> disconnectFromDevice() async {
    // Correction ici : utilisez la variable _activeProtocol
    if (_activeProtocol == BluetoothProtocol.classic) {
      await _classicManager.disconnect();
    } else if (_activeProtocol == BluetoothProtocol.ble) {
      await _bleManager.disconnect();
    }
    _connectionStateController.add(false); // Signale la déconnexion
    print('BluetoothCommunicationManager: Déconnecté via $_activeProtocol.');
  }

  /// [serviceUuid] et [characteristicUuid] sont obligatoires pour BLE si le protocole BLE est actif.
  Future<void> sendCommand(String command, {String? serviceUuid, String? characteristicUuid}) async {
    if (_activeProtocol == BluetoothProtocol.classic) {
      await _classicManager.sendData(command);
    } else if (_activeProtocol == BluetoothProtocol.ble) {
      if (serviceUuid == null || characteristicUuid == null) {
        throw Exception('Pour BLE, serviceUuid et characteristicUuid sont requis pour envoyer une commande.');
      }
      await _bleManager.sendCommandToUuid(
        command,
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
      );
    } else {
      throw Exception('Aucun protocole Bluetooth actif sélectionné pour envoyer la commande.');
    }
    print('BluetoothCommunicationManager: Commande envoyée: "$command" via $_activeProtocol.');
  }

  // --- Fonctions d'Appairage (principalement pour Classic) ---

  /// Récupère la liste des appareils appairés (principalement pour Classic).
  /// Retourne une liste de BluetoothDevice (notre modèle commun).
  Future<List<BluetoothDevice>> getBondedDevices({BluetoothProtocol protocol = BluetoothProtocol.classic}) async {
    if (protocol == BluetoothProtocol.classic) {
      return await _classicManager.getBondedDevices(); // Renvoie déjà le modèle commun
    } else if (protocol == BluetoothProtocol.ble) {
      return _bleManager.getBondedDevices(); // Retourne une liste vide pour BLE
    } else {
      return [];
    }
  }

  /// Tente d'appairer un appareil Bluetooth (principalement Classic).
  Future<void> bondDevice(BluetoothDevice device) async {
    if (!device.isBle) { // L'appairage est plus pertinent pour Classic
      await _classicManager.bondDevice(device); // Passe directement votre modèle commun
      print('BluetoothCommunicationManager: Appareil appairé: ${device.name}.');
    } else {
      print('BluetoothCommunicationManager: L\'appairage n\'est pas typique pour BLE via cette méthode.');
    }
  }

  /// Tente de désappairer un appareil Bluetooth (principalement Classic).
  Future<void> unbondDevice(BluetoothDevice device) async {
    if (!device.isBle) { // Le désappairage est plus pertinent pour Classic
      await _classicManager.unbondDevice(device); // Passe directement votre modèle commun
      print('BluetoothCommunicationManager: Appareil désappairé: ${device.name}.');
    } else {
      print('BluetoothCommunicationManager: Le désappairage n\'est pas applicable pour BLE via cette méthode.');
    }
  }

  // --- Gestion générale des connexions Bluetooth ---

  void disconnectAllBluetoothConnections() {
    print('BluetoothCommunicationManager: Déconnexion de toutes les connexions Bluetooth actives.');
    _classicManager.disconnect();
    _bleManager.disconnect();
    _activeProtocol = BluetoothProtocol.none;
    _connectionStateController.add(false); // S'assurer que l'état de connexion est mis à jour
  }

  // Libération des ressources
  void dispose() {
    _classicManager.dispose();
    _bleManager.dispose();
    _discoveredDevicesController.close();
    _receivedDataController.close();
    _connectionStateController.close();
    _bluetoothEnabledController.close();
  }
}

/// Modèle simple pour représenter un appareil Bluetooth détecté (commun aux deux protocoles)
class BluetoothDevice {
  final String id;
  final String name;
  final bool isBle;

  BluetoothDevice({
    required this.id,
    required this.name,
    required this.isBle,
  });

  // Pour éviter les doublons dans une Set ou une liste
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BluetoothDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}