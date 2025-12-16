import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:claude_iot/pages/bluetooth_widget.dart';

// Classe de gestion des données persistantes (Singleton)
class DataSaver {
  // Instance unique de la classe (Singleton)
  static final DataSaver _instance = DataSaver._internal();

  // Clés de stockage
  static const _controlsKey = 'controls';

  // Constructeur privé pour le singleton
  DataSaver._internal();

  // Méthode pour obtenir l'instance unique
  factory DataSaver() {
    return _instance;
  }

  // --- Méthodes de sauvegarde ---

  Future<bool> saveControls(List<DeviceControl> controls) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> controlsJson = controls.map((control) {
        return json.encode({
          'name': control.name,
          'onCommand': control.onCommand,
          'offCommand': control.offCommand,
          'iconCodePoint': control.icon.codePoint,
          'iconFontFamily': control.icon.fontFamily,
          'isActive': control.isActive,
        });
      }).toList();
      return await prefs.setStringList(_controlsKey, controlsJson);
    } catch (e) {
      debugPrint("Erreur lors de la sauvegarde des contrôles: $e");
      return false;
    }
  }

  // --- Méthodes de chargement ---

  Future<List<DeviceControl>> loadControls() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final controlsJson = prefs.getStringList(_controlsKey);

      if (controlsJson == null || controlsJson.isEmpty) {
        debugPrint("Aucune donnée de contrôle trouvée. Retourne une liste vide.");
        return [];
      }

      return controlsJson.map((jsonString) {
        final Map<String, dynamic> data = json.decode(jsonString);
        return DeviceControl(
          name: data['name'],
          onCommand: data['onCommand'],
          offCommand: data['offCommand'],
          icon: IconData(
            data['iconCodePoint'],
            fontFamily: data['iconFontFamily'] ?? 'MaterialIcons',
          ),
          isActive: data['isActive'],
        );
      }).toList();
    } catch (e) {
      debugPrint("Erreur lors du chargement des contrôles: $e");
      return [];
    }
  }
}