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

  PersistBluetoothDevice({
    required this.id,
    required this.name,
    required this.isBle,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'isBle': isBle,
    };
  }

  factory PersistBluetoothDevice.fromMap(Map<String, dynamic> map) {
    return PersistBluetoothDevice(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Inconnu',
      isBle: map['isBle'] ?? false,
    );
  }
}

// ============ SERVICE DE PERSISTANCE ============
class ConnectionPersistence {
  static const String _connectionKey = 'saved_connection';

  // Sauvegarde d'une connexion
  static Future<void> saveConnection({
    required PersistConnectionMode mode,
    PersistBluetoothDevice? bluetoothDevice,
    String? wifiIp,
    int? wifiPort,
    PersistWiFiProtocol? wifiProtocol,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'mode': mode.index,
      'bluetoothDevice': bluetoothDevice != null ? jsonEncode(bluetoothDevice.toMap()) : null,
      'wifiIp': wifiIp,
      'wifiPort': wifiPort,
      'wifiProtocol': wifiProtocol?.index,
      'isConnected': true,
    };
    await prefs.setString(_connectionKey, jsonEncode(data));
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

  // Effacement de la connexion sauvegardée
  static Future<void> clearConnection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_connectionKey);
  }

  // Vérification de l'existence d'une connexion sauvegardée
  static Future<bool> isConnectionSaved() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_connectionKey);
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