import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter/material.dart';

/// Classe pour gérer le Bluetooth BLE avec flutter_reactive_ble
class BluetoothReactiveManager {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  // Stream pour l'état de connexion
  Stream<ConnectionStateUpdate>? _connectionStream;
  // Subscription pour la connexion
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;

  // Subscription pour le scan BLE
  StreamSubscription<DiscoveredDevice>? _scanSubscription;

  // L'appareil actuellement connecté
  DiscoveredDevice? connectedDevice;
  // Dernier état de connexion
  ConnectionStateUpdate? lastConnectionState;

  BluetoothReactiveManager();

  /// Scanner les appareils BLE à proximité
  Future<List<DiscoveredDevice>> scanDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final List<DiscoveredDevice> foundDevices = [];
    final completer = Completer<List<DiscoveredDevice>>();

    // Arrête tout scan en cours
    await stopScan();

    // Lance le scan
    _scanSubscription = _ble.scanForDevices(withServices: []).listen(
      (device) {
        // Ajoute l'appareil s'il n'est pas déjà dans la liste
        if (!foundDevices.any((d) => d.id == device.id)) {
          foundDevices.add(device);
        }
      },
      onError: (e) {
        completer.completeError('Erreur scan BLE : $e');
      },
    );

    // Arrête le scan après le timeout
    Future.delayed(timeout, () async {
      await stopScan();
      if (!completer.isCompleted) {
        completer.complete(foundDevices);
      }
    });

    return completer.future;
  }

  /// Arrête le scan BLE en cours
  Future<void> stopScan() async {
    try {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    } catch (_) {
      // Ignore les erreurs d'arrêt de scan
    }
  }

  /// Se connecter à un appareil BLE
  Future<void> connect(String deviceId) async {
    // Annule toute connexion précédente
    await disconnect();

    // Démarre la connexion
    _connectionStream = _ble.connectToDevice(id: deviceId);
    _connectionSub = _connectionStream!.listen(
      (update) {
        lastConnectionState = update;
        if (update.connectionState == DeviceConnectionState.connected) {
          connectedDevice = DiscoveredDevice(
            id: deviceId,
            name: '', // Peut être rempli lors du scan si besoin
            serviceUuids: const [],
            manufacturerData: Uint8List(0),
            serviceData: const {},
            rssi: 0,
          );
        } else if (update.connectionState == DeviceConnectionState.disconnected) {
          connectedDevice = null;
        }
      },
      onError: (e) {
        debugPrint('Erreur connexion BLE : $e');
      },
    );
  }

  /// Déconnecter l'appareil BLE
  Future<void> disconnect() async {
    await _connectionSub?.cancel();
    _connectionSub = null;
    connectedDevice = null;
  }

  /// Découvre dynamiquement le premier service et la première caractéristique écrivable
  Future<Map<String, dynamic>> discoverServicesAndCharacteristics(
    String deviceId,
  ) async {
    final services = await _ble.discoverServices(deviceId);
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.isWritableWithResponse ||
            characteristic.isWritableWithoutResponse) {
          return {
            'serviceUuid': service.serviceId,
            'characteristicUuid': characteristic.characteristicId,
          };
        }
      }
    }
    throw Exception('Aucune caractéristique écrivable trouvée');
  }

  /// Envoie une commande à une caractéristique précise (UUID dynamique)
  Future<void> sendCommandToUuid(
    String command, {
    required Uuid serviceUuid,
    required Uuid characteristicUuid,
  }) async {
    if (connectedDevice == null) throw Exception('Aucun appareil connecté');
    final data = Uint8List.fromList(command.codeUnits);

    try {
      await _ble.writeCharacteristicWithResponse(
        QualifiedCharacteristic(
          serviceId: serviceUuid,
          characteristicId: characteristicUuid,
          deviceId: connectedDevice!.id,
        ),
        value: data,
      );
    } catch (e) {
      throw Exception('Erreur envoi commande BLE : $e');
    }
  }

  /// Nettoyer les ressources
  void dispose() {
    stopScan();
    disconnect();
  }
}