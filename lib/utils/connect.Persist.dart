// utils/connection_persistence.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ============ MODÈLES DE PERSISTANCE ============
enum PersistConnectionMode { none, bluetooth, wifi }

enum PersistWiFiProtocol { http, websocket }

class PersistBluetoothDevice {
  final String id;
  final String name;
  final bool isBle;
  final String? deviceType; // 'classic' ou 'ble'

  PersistBluetoothDevice({
    required this.id,
    required this.name,
    required this.isBle,
    this.deviceType,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'isBle': isBle,
      'deviceType': deviceType,
    };
  }

  factory PersistBluetoothDevice.fromMap(Map<String, dynamic> map) {
    return PersistBluetoothDevice(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Inconnu',
      isBle: map['isBle'] ?? false,
      deviceType: map['deviceType'],
    );
  }
}

// ============ SERVICE DE PERSISTANCE AMÉLIORÉ ============
class ConnectionPersistence {
  static const String _connectionKey = 'saved_connection';
  static const String _lastConnectedKey = 'last_connected_device';
  static const String _autoReconnectKey = 'auto_reconnect_enabled';

  // Sauvegarde d'une connexion Bluetooth
  static Future<void> saveBluetoothConnection({
    required PersistBluetoothDevice device,
    required bool isBle,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'mode': PersistConnectionMode.bluetooth.index,
      'bluetoothDevice': jsonEncode(device.toMap()),
      'isBle': isBle,
      'deviceType': isBle ? 'ble' : 'classic',
      'isConnected': true,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(_connectionKey, jsonEncode(data));
    
    // Sauvegarder aussi comme dernier appareil connecté
    await prefs.setString(_lastConnectedKey, jsonEncode(device.toMap()));
  }

  // Récupération de la connexion sauvegardée
  static Future<Map<String, dynamic>?> getSavedConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_connectionKey);
    if (data != null) {
      return jsonDecode(data);
    }
    return null;
  }

  // Récupérer le dernier appareil connecté
  static Future<PersistBluetoothDevice?> getLastConnectedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_lastConnectedKey);
    if (data != null) {
      final deviceMap = jsonDecode(data);
      return PersistBluetoothDevice.fromMap(deviceMap);
    }
    return null;
  }

  // Effacement de la connexion sauvegardée
  static Future<void> clearConnection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_connectionKey);
  }

  // Marquer comme déconnecté (mais garder l'appareil pour reconnexion auto)
  static Future<void> markAsDisconnected() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_connectionKey);
    if (data != null) {
      final connectionData = jsonDecode(data);
      connectionData['isConnected'] = false;
      await prefs.setString(_connectionKey, jsonEncode(connectionData));
    }
  }

  // Vérification de l'existence d'une connexion sauvegardée
  static Future<bool> isConnectionSaved() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_connectionKey);
  }

  // Activer/désactiver la reconnexion automatique
  static Future<void> setAutoReconnect(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoReconnectKey, enabled);
  }

  // Vérifier si la reconnexion automatique est activée
  static Future<bool> isAutoReconnectEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoReconnectKey) ?? true; // Activé par défaut
  }

  // Vérifier si la connexion est encore "fraîche" (moins de 5 minutes)
  static Future<bool> isConnectionRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_connectionKey);
    if (data != null) {
      final connectionData = jsonDecode(data);
      final timestamp = connectionData['timestamp'] as int?;
      if (timestamp != null) {
        final connectionTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final now = DateTime.now();
        return now.difference(connectionTime).inMinutes < 5;
      }
    }
    return false;
  }

  // ============ UTILITAIRES DE CONVERSION ============
  
  // Convertit un PersistConnectionMode en String
  static String modeToString(PersistConnectionMode mode) {
    switch (mode) {
      case PersistConnectionMode.bluetooth:
        return 'Bluetooth';
      case PersistConnectionMode.wifi:
        return 'Wi-Fi';
      default:
        return 'Non connecté';
    }
  }

  // Convertit un PersistWiFiProtocol en String
  static String protocolToString(PersistWiFiProtocol protocol) {
    switch (protocol) {
      case PersistWiFiProtocol.http:
        return 'HTTP';
      case PersistWiFiProtocol.websocket:
        return 'WebSocket';
    }
  }

  // Obtient l'icône associée au mode de connexion
  static String modeIcon(PersistConnectionMode mode) {
    switch (mode) {
      case PersistConnectionMode.bluetooth:
        return 'bluetooth';
      case PersistConnectionMode.wifi:
        return 'wifi';
      default:
        return 'link_off';
    }
  }
}