import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';


class BluetoothClassicManager {
  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  final _discoveredDevicesController = StreamController<List<BluetoothDevice>>.broadcast();
  Stream<List<BluetoothDevice>> get discoveredDevicesStream => _discoveredDevicesController.stream;
  // Flux de découverte et connexion
  StreamSubscription<BluetoothDiscoveryResult>? _discoveryStream;
  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _dataSubscription;

  // État Bluetooth global
  StreamSubscription<BluetoothState>? _bluetoothStateSub;

  // Appareil actuellement connecté
  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isConnected => _connection?.isConnected ?? false;

  // Buffer pour données reçues et stream de sortie
  final StreamController<String> _dataStreamController = StreamController.broadcast();
  Stream<String> get dataStream => _dataStreamController.stream;

  // Contrôleur pour les changements d'état de connexion
  final StreamController<bool> _connectionStateController = StreamController.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  BluetoothClassicManager() {
    // Surveiller les changements d'état global du Bluetooth
    _bluetoothStateSub = _bluetooth.onStateChanged().listen((state) {
      
      // Déconnecter automatiquement si Bluetooth désactivé
      if (state != BluetoothState.STATE_ON) {
        _disconnect();
        _connectionStateController.add(false);
      }
    });
  }

  /// Vérifie si le Bluetooth est activé
Future<bool> isBluetoothEnabled() async {
  try {
    return await _bluetooth.isEnabled ?? false;
  } catch (e) {
    throw Exception('Erreur vérification Bluetooth: ${e.toString()}');
  }
}
  /// Vérifie si le Bluetooth est activé
  Future<bool> get isEnabled async => await _bluetooth.isEnabled ?? false;

  /// Active ou désactive le Bluetooth
  Future<void> setEnable(bool enable) async {
    if (enable) {
      await _bluetooth.requestEnable();
    } else {
      await _bluetooth.requestDisable();
    }
  }

  /// Récupère la liste des appareils déjà appairés
  Future<List<BluetoothDevice>> getBondedDevices() async {
    return await _bluetooth.getBondedDevices() ?? [];
  }

  // blue_classic.dart
Future<List<BluetoothDevice>> scanDevices({
  Duration timeout = const Duration(seconds: 10),
  bool pairedOnly = false,
}) async {
  final statuses = await [
    Permission.location,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ].request();

  if (statuses.values.any((status) => !status.isGranted)) {
    throw Exception('Permissions Bluetooth non accordées');
  }
  _dataStreamController.add('DÉBUT DU SCAN...');
    final completer = Completer<List<BluetoothDevice>>();
    final devices = <BluetoothDevice>[];
    final seenAddresses = <String>{};

  try {
    if (!(await isEnabled)) throw BluetoothDisabledException();
    
    if (pairedOnly) {
      completer.complete(await getBondedDevices());
    } else {
        _discoveryStream = _bluetooth.startDiscovery().listen(
          (result) {
            final device = result.device;
            if (!seenAddresses.contains(device.address)) {
              seenAddresses.add(device.address);
              devices.add(device);
              // Émettre la liste mise à jour via le stream
              _discoveredDevicesController.add([...devices]);
          }
        },
        onError: (error) => completer.completeError(BluetoothScanException(error.toString())),
        cancelOnError: true,
      );

      Future.delayed(timeout, () {
        if (!completer.isCompleted) {
          _discoveryStream?.cancel();
          completer.complete(devices);
        }
      });
    }

    return await completer.future;
  } catch (e) {
    _dataStreamController.add('ERREUR SCAN Classic: ${e.toString()}');
    throw BluetoothScanException('Échec du scan: ${e.toString()}');
  }
}

  /// Arrête le scan en cours
  Future<void> stopScan() async {
    await _discoveryStream?.cancel();
    _discoveryStream = null;
  }

  /// Établit une connexion à un appareil Bluetooth
  /// 
  /// [device] : Appareil cible
  /// [timeout] : Délai maximal de connexion
  Future<void> connect(
    BluetoothDevice device, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // Vérifications préalables
    if (!(await isEnabled)) throw BluetoothDisabledException();
    if (isConnected && _connectedDevice?.address == device.address) return;
    
    // Déconnexion propre si nécessaire
    await _disconnect();

    try {
      // Établissement de connexion avec timeout
      _connection = await BluetoothConnection.toAddress(device.address)
          .timeout(timeout, onTimeout: () {
            throw BluetoothConnectionTimeoutException();
          });

      _connectedDevice = device;
      
      // Configuration du flux de données entrantes
      _dataSubscription = _connection!.input!.listen(
        _handleIncomingData,
        onError: (error) => _handleConnectionError(error),
        onDone: () => _disconnect(),
      );

      // Notification de changement d'état
      _connectionStateController.add(true);
    } catch (e) {
      await _disconnect();
      throw BluetoothConnectionException('Échec connexion: ${e.toString()}');
    }
  }

  /// Gestion des erreurs de connexion
  void _handleConnectionError(dynamic error) {
    _dataStreamController.addError(BluetoothDataException(error.toString()));
    _disconnect();
    _connectionStateController.add(false);
  }

  /// Traite les données entrantes
  void _handleIncomingData(Uint8List data) {
    try {
      // Tentative de décodage UTF-8
      _dataStreamController.add(utf8.decode(data));
    } catch (e) {
      // Fallback: Affichage hexadécimal
      _dataStreamController.add(
        'HEX: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}'
      );
    }
  }

  /// Envoie des données textuelles à l'appareil connecté
  Future<void> sendData(String data) async {
    if (!isConnected) throw BluetoothNotConnectedException();
    
    try {
      await sendBytes(Uint8List.fromList(utf8.encode(data)));
    } catch (e) {
      throw BluetoothDataException('Erreur envoi texte: ${e.toString()}');
    }
  }

  /// Envoie des données binaires à l'appareil connecté
  Future<void> sendBytes(Uint8List data) async {
    if (!isConnected) throw BluetoothNotConnectedException();
    
    try {
      _connection!.output.add(data);
      await _connection!.output.allSent;
    } catch (e) {
      throw BluetoothDataException('Erreur envoi binaire: ${e.toString()}');
    }
  }

  /// Déconnexion interne (nettoyage des ressources)
  Future<void> _disconnect() async {
    try {
      await _dataSubscription?.cancel();
      await _connection?.finish();
    } catch (e) {
      // Ignorer les erreurs de déconnexion
    } finally {
      _connection = null;
      _connectedDevice = null;
      _dataSubscription = null;
      _connectionStateController.add(false);
      _dataStreamController.add('DÉCONNECTÉ');
    }
  }

  /// Déconnexion publique
  Future<void> disconnect() async => await _disconnect();

  /// Appaire un appareil (Android uniquement)
Future<void> bondDevice(BluetoothDevice device) async {
  try {
    final bool? result = await _bluetooth.bondDeviceAtAddress(device.address);
    
    if (result == null) {
      throw BluetoothPairingException('Réponse nulle du système');
    } else if (!result) {
      throw BluetoothPairingException('Échec de l\'appairage (réponse système: false)');
    }
    // Si result est true, l'appairage a réussi
  } catch (e) {
    throw BluetoothPairingException('Erreur technique: ${e.toString()}');
  }
}

  /// Supprime un appareil appairé (Android uniquement)
  /// Supprime un appareil appairé (Android uniquement)
Future<void> unbondDevice(BluetoothDevice device) async {
  try {
    final bool? success = await _bluetooth.removeDeviceBondWithAddress(device.address);
    
    // Vérification robuste du résultat (gère le cas null et false)
    if (success == null || !success) {
      throw BluetoothPairingException(
        success == null 
          ? 'Réponse nulle du système' 
          : 'Échec explicite du désappairage'
      );
    }
  } catch (e) {
    throw BluetoothPairingException('Erreur technique: ${e.toString()}');
  }
}

  /// Vérifie si un appareil est appairé
  Future<bool> isDeviceBonded(BluetoothDevice device) async {
    try {
      final bondedDevices = await getBondedDevices();
      return bondedDevices.any((d) => d.address == device.address);
    } catch (e) {
      throw BluetoothPairingException(e.toString());
    }
  }

  /// Libération des ressources
  Future<void> dispose() async {
    await _disconnect();
    await _bluetoothStateSub?.cancel();
    await _discoveryStream?.cancel();
    await _connectionStateController.close();
    await _dataStreamController.close();
    await _discoveredDevicesController.close();
  }
}

// ================= EXCEPTIONS PERSONNALISÉES =================
class BluetoothDisabledException implements Exception {
  final String message = 'Bluetooth désactivé';
  @override
  String toString() => message;
}

class BluetoothNotConnectedException implements Exception {
  final String message = 'Aucun appareil connecté';
  @override
  String toString() => message;
}

class BluetoothConnectionException implements Exception {
  final String message;
  BluetoothConnectionException(this.message);
  @override
  String toString() => message;
}

class BluetoothConnectionTimeoutException implements Exception {
  final String message = 'Timeout de connexion';
  @override
  String toString() => message;
}

class BluetoothScanException implements Exception {
  final String message;
  BluetoothScanException(this.message);
  @override
  String toString() => message;
}

class BluetoothDataException implements Exception {
  final String message;
  BluetoothDataException(this.message);
  @override
  String toString() => message;
}

class BluetoothPairingException implements Exception {
  final String message;
  BluetoothPairingException(this.message);
  @override
  String toString() => message;
}