import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:claude_iot/services/services.bluetooth.dart'; // Importe le modèle BluetoothDevice depuis le service

class BluetoothBluePlus {
  final _discoveredDevicesController = StreamController<List<BluetoothDevice>>.broadcast();
  Stream<List<BluetoothDevice>> get discoveredDevicesStream => _discoveredDevicesController.stream;

  StreamSubscription<List<fbp.ScanResult>>? _scanSubscription;
  fbp.BluetoothDevice? _connectedBleDevice;
  final StreamController<String> _receivedDataController = StreamController<String>.broadcast();
  Stream<String>? get receivedDataStream => _receivedDataController.stream;

  Future<List<BluetoothDevice>> scanDevices(int duration) async {
    final devices = <BluetoothDevice>[];
    final seenDevices = <String>{};

    try {
      _receivedDataController.add('DÉBUT DU SCAN BLE...');
      await stopScan(); // Assurez-vous d'arrêter tout scan précédent

      _scanSubscription = fbp.FlutterBluePlus.scanResults.listen((results) {
        for (fbp.ScanResult result in results) {
          final deviceId = result.device.remoteId.str;
          if (!seenDevices.contains(deviceId)) {
            seenDevices.add(deviceId);
            devices.add(BluetoothDevice(
              id: deviceId,
              name: result.device.name.isNotEmpty 
                  ? result.device.name 
                  : 'Appareil inconnu',
              isBle: true,
            ));
            _discoveredDevicesController.add([...devices]); // Émettre les appareils au fur et à mesure
          }
        }
      });

      await fbp.FlutterBluePlus.startScan(timeout: Duration(seconds: duration));
      await Future.delayed(Duration(seconds: duration)); // Attendre la durée du scan
      await stopScan(); // Arrêter le scan après la durée

      return devices; // Retourne la liste finale des appareils
    } catch (e) {
      _receivedDataController.add('ERREUR SCAN BLE: $e');
      await stopScan();
      throw Exception('Erreur scan BLE: $e');
    }
  }

  Future<void> initialize() async {
    try {
      final status = await Permission.bluetoothScan.request();
      if (!status.isGranted) {
        throw Exception('Permissions Bluetooth non accordées');
      }

      final isOn = await fbp.FlutterBluePlus.isOn;
      if (!isOn) {
        throw Exception('Bluetooth non activé');
      }
    } catch (e) {
      throw Exception('Erreur initialisation BLE: $e');
    }
  }
  
  /// Arrête le scan BLE en cours
  Future<void> stopScan() async {
    try {
      await fbp.FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    } catch (_) {
      // Ignore les erreurs d'arrêt de scan
    }
  }

  /// Se connecte à un appareil BLE via son [deviceId]
  Future<void> connect(String deviceId) async {
    try {
      final device = fbp.BluetoothDevice.fromId(deviceId);
      await device.connect(autoConnect: false);
      _connectedBleDevice = device;

      device.connectionState.listen((state) {
        if (state == fbp.BluetoothConnectionState.disconnected) {
          _connectedBleDevice = null;
        }
      });
    } catch (e) {
      throw Exception('Erreur connexion BLE: $e');
    }
  }

  /// Déconnecte l'appareil BLE actuellement connecté
  Future<void> disconnect() async {
    try {
      if (_connectedBleDevice != null) {
        await _connectedBleDevice!.disconnect();
        _connectedBleDevice = null;
      }
    } catch (e) {
      throw Exception('Erreur déconnexion BLE: $e');
    }
  }

  /// Découvre dynamiquement le premier service et la première caractéristique écrivable
  Future<Map<String, dynamic>> discoverServicesAndCharacteristics(String deviceId) async {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    final services = await device.discoverServices();
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
          return {
            'serviceUuid': service.uuid.toString(),
            'characteristicUuid': characteristic.uuid.toString(),
          };
        }
      }
    }
    throw Exception('Aucune caractéristique écrivable trouvée');
  }

  /// Envoie une commande à une caractéristique précise (UUID dynamique)
  Future<void> sendCommandToUuid(
    String command, {
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    if (_connectedBleDevice == null) throw Exception('Aucun appareil connecté');
    
    final services = await _connectedBleDevice!.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid.toString() == serviceUuid,
      orElse: () => throw Exception('Service non trouvé')
    );
    
    final characteristic = service.characteristics.firstWhere(
      (c) => c.uuid.toString() == characteristicUuid,
      orElse: () => throw Exception('Caractéristique non trouvée')
    );
    
    await characteristic.write(command.codeUnits);
  }

  /// Getter pour l'appareil connecté (pour le manager)
  fbp.BluetoothDevice? get connectedDevice => _connectedBleDevice;

  /// Nettoie les ressources (à appeler dans dispose)
  void dispose() {
    stopScan();
    disconnect();
    _discoveredDevicesController.close();
  }

  /// Vérifie si le Bluetooth est activé
  Future<bool> isBluetoothEnabled() async {
  try {
    return await fbp.FlutterBluePlus.isOn;
  } catch (e) {
    throw Exception('Erreur vérification BLE: ${e.toString()}');
  }
}

  /// Récupère les appareils appairés (vide pour BLE)
  Future<List<BluetoothDevice>> getBondedDevices() async {
    return []; // BLE ne gère pas les appareils appairés comme Classic
  }
}