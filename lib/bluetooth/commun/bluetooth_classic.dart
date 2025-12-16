import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as fbs; // Alias pour éviter les conflits
import 'package:claude_iot/services/services.bluetooth.dart'; // Importe le modèle BluetoothDevice depuis le service

class BluetoothClassicManager {
  final fbs.FlutterBluetoothSerial _bluetooth = fbs.FlutterBluetoothSerial.instance;
  final _discoveredDevicesController = StreamController<List<BluetoothDevice>>.broadcast();
  Stream<List<BluetoothDevice>> get discoveredDevicesStream => _discoveredDevicesController.stream;
  
  StreamSubscription<fbs.BluetoothDiscoveryResult>? _discoveryStream;
  fbs.BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _dataSubscription;

  StreamSubscription<fbs.BluetoothState>? _bluetoothStateSub;

  BluetoothDevice? _connectedDevice; // Utilise votre modèle commun
  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isConnected => _connection?.isConnected ?? false;

  final StreamController<String> _dataStreamController = StreamController.broadcast();
  Stream<String> get dataStream => _dataStreamController.stream;

  final StreamController<bool> _connectionStateController = StreamController.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  BluetoothClassicManager() {
    _bluetoothStateSub = _bluetooth.onStateChanged().listen((state) {
      if (state != fbs.BluetoothState.STATE_ON) {
        _disconnect();
        _connectionStateController.add(false);
      }
    });
  }

  Future<bool> isBluetoothEnabled() async {
    try {
      return await _bluetooth.isEnabled ?? false;
    } catch (e) {
      throw Exception('Erreur vérification Bluetooth: ${e.toString()}');
    }
  }

  Future<bool> get isEnabled async => await _bluetooth.isEnabled ?? false;

  Future<void> setEnable(bool enable) async {
    if (enable) {
      await _bluetooth.requestEnable();
    } else {
      await _bluetooth.requestDisable();
    }
  }

  /// Récupère la liste des appareils déjà appairés et les mappe vers votre modèle commun.
  Future<List<BluetoothDevice>> getBondedDevices() async {
    final bondedFbsDevices = await _bluetooth.getBondedDevices();
    return bondedFbsDevices.map((d) => BluetoothDevice(
      id: d.address,
      name: d.name ?? 'Appareil inconnu',
      isBle: false,
    )).toList();
  }

  /// Scanne les appareils Bluetooth Classic et retourne une liste de votre modèle commun.
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
    final devices = <BluetoothDevice>[]; // Cette liste contient votre modèle commun
    final seenAddresses = <String>{};

    try {
      if (!(await isEnabled)) throw BluetoothDisabledException();
      
      if (pairedOnly) {
        // Appelle la version mappée de getBondedDevices
        completer.complete(await getBondedDevices());
      } else {
        _discoveryStream = _bluetooth.startDiscovery().listen(
          (result) {
            final fbsDevice = result.device; // C'est un appareil fbs.BluetoothDevice
            if (!seenAddresses.contains(fbsDevice.address)) {
              seenAddresses.add(fbsDevice.address);
              
              // Mappez le fbs.BluetoothDevice vers votre modèle commun BluetoothDevice
              final commonDevice = BluetoothDevice(
                id: fbsDevice.address,
                name: fbsDevice.name ?? 'Appareil inconnu',
                isBle: false, // C'est un appareil Classic
              );
              devices.add(commonDevice);

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
            completer.complete(devices); // 'devices' contient déjà les bons objets mappés
          }
        });
      }

      return await completer.future;
    } catch (e) {
      _dataStreamController.add('ERREUR SCAN Classic: ${e.toString()}');
      throw BluetoothScanException('Échec du scan: ${e.toString()}');
    }
  }

  Future<void> stopScan() async {
    await _discoveryStream?.cancel();
    _discoveryStream = null;
  }

  Future<void> connect(
    BluetoothDevice device, { // Prend votre modèle commun BluetoothDevice
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!(await isEnabled)) throw BluetoothDisabledException();
    if (isConnected && _connectedDevice?.id == device.id) return; // Utilise device.id

    await _disconnect();

    try {
      _connection = await fbs.BluetoothConnection.toAddress(device.id) // Utilise device.id pour l'adresse
          .timeout(timeout, onTimeout: () {
            throw BluetoothConnectionTimeoutException();
          });

      _connectedDevice = device;
      
      _dataSubscription = _connection!.input!.listen(
        _handleIncomingData,
        onError: (error) => _handleConnectionError(error),
        onDone: () => _disconnect(),
      );

      _connectionStateController.add(true);
    } catch (e) {
      await _disconnect();
      throw BluetoothConnectionException('Échec connexion: ${e.toString()}');
    }
  }

  void _handleConnectionError(dynamic error) {
    _dataStreamController.addError(BluetoothDataException(error.toString()));
    _disconnect();
    _connectionStateController.add(false);
  }

  void _handleIncomingData(Uint8List data) {
    try {
      _dataStreamController.add(utf8.decode(data));
    } catch (e) {
      _dataStreamController.add(
        'HEX: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}'
      );
    }
  }

  Future<void> sendData(String data) async {
    if (!isConnected) throw BluetoothNotConnectedException();
    
    try {
      await sendBytes(Uint8List.fromList(utf8.encode(data)));
    } catch (e) {
      throw BluetoothDataException('Erreur envoi texte: ${e.toString()}');
    }
  }

  Future<void> sendBytes(Uint8List data) async {
    if (!isConnected) throw BluetoothNotConnectedException();
    
    try {
      _connection!.output.add(data);
      await _connection!.output.allSent;
    } catch (e) {
      throw BluetoothDataException('Erreur envoi binaire: ${e.toString()}');
    }
  }

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

  Future<void> disconnect() async => await _disconnect();

  Future<void> bondDevice(BluetoothDevice device) async { // Prend votre modèle commun
    try {
      final bool? result = await _bluetooth.bondDeviceAtAddress(device.id); // Utilise device.id pour l'adresse
      
      if (result == null) {
        throw BluetoothPairingException('Réponse nulle du système');
      } else if (!result) {
        throw BluetoothPairingException('Échec de l\'appairage (réponse système: false)');
      }
    } catch (e) {
      throw BluetoothPairingException('Erreur technique: ${e.toString()}');
    }
  }

  Future<void> unbondDevice(BluetoothDevice device) async { // Prend votre modèle commun
    try {
      final bool? success = await _bluetooth.removeDeviceBondWithAddress(device.id); // Utilise device.id pour l'adresse
      
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

  Future<bool> isDeviceBonded(BluetoothDevice device) async { // Prend votre modèle commun
    try {
      final bondedDevices = await getBondedDevices(); // getBondedDevices retourne déjà le bon type
      return bondedDevices.any((d) => d.id == device.id); // Utilise d.id
    } catch (e) {
      throw BluetoothPairingException(e.toString());
    }
  }

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