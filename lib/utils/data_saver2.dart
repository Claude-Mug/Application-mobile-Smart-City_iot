import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:claude_iot/pages/wifi_control_widget.dart';

// Classe de gestion des données persistantes pour le WiFi (Singleton)
class DataSaver2 {
  static final DataSaver2 _instance = DataSaver2._internal();
  
  // Clé de stockage spécifique au WiFi pour éviter les conflits
  static const _wifiControlsKey = 'wifi_controls';
  static const _versionKey = 'wifi_controls_version';
  static const _currentVersion = 2; // Version du format de données

  DataSaver2._internal();

  factory DataSaver2() {
    return _instance;
  }

  // Méthode de sauvegarde sophistiquée avec gestion de version
  Future<SaveResult> saveControls(List<DeviceControl> controls) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Préparer les données avec version
      final List<String> controlsJson = controls.map((control) {
        final data = {
          'version': _currentVersion,
          'name': control.name,
          'onCommand': control.onCommand,
          'offCommand': control.offCommand,
          'isActive': control.isActive ?? false,
          'iconCodePoint': control.icon.codePoint,
          'iconFontFamily': control.icon.fontFamily,
          // ID optionnel - seulement si présent
          if (control.id != null) 'id': control.id,
          // Timestamp de création
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        };
        return json.encode(data);
      }).toList();

      // Sauvegarder les données et la version
      final success = await prefs.setStringList(_wifiControlsKey, controlsJson);
      await prefs.setInt(_versionKey, _currentVersion);
      
      return SaveResult(
        success: success,
        itemsSaved: controls.length,
        timestamp: DateTime.now(),
      );
    } catch (e, stackTrace) {
      debugPrint("Erreur lors de la sauvegarde des contrôles WiFi: $e");
      debugPrint("Stack trace: $stackTrace");
      
      return SaveResult(
        success: false,
        error: e.toString(),
        timestamp: DateTime.now(),
      );
    }
  }

  // Méthode de chargement sophistiquée avec migration et gestion d'erreurs
  Future<LoadResult<List<DeviceControl>>> loadControls() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final controlsJson = prefs.getStringList(_wifiControlsKey);
      final savedVersion = prefs.getInt(_versionKey) ?? 1;

      if (controlsJson == null || controlsJson.isEmpty) {
        debugPrint("Aucune donnée de contrôle WiFi trouvée.");
        return LoadResult(
          data: [],
          isEmpty: true,
          timestamp: DateTime.now(),
        );
      }

      final List<DeviceControl> loadedControls = [];
      int migrationCount = 0;
      int errorCount = 0;

      for (int i = 0; i < controlsJson.length; i++) {
        try {
          final jsonString = controlsJson[i];
          final Map<String, dynamic> data = json.decode(jsonString);
          
          // Migration depuis les anciennes versions
          final migratedData = _migrateData(data, savedVersion);
          
          // Générer un ID si manquant (compatibilité avec anciennes versions)
          final int deviceId = migratedData['id'] ?? 
                              DateTime.now().millisecondsSinceEpoch + i;
          
          // Gestion robuste de l'icône
          final IconData iconData = _parseIconData(migratedData);
          
          final control = DeviceControl(
            id: deviceId,
            name: migratedData['name'] as String? ?? 'Appareil sans nom',
            onCommand: migratedData['onCommand'] as String? ?? 'ON',
            offCommand: migratedData['offCommand'] as String? ?? 'OFF',
            icon: iconData,
            isActive: migratedData['isActive'] as bool? ?? false,
          );
          
          loadedControls.add(control);
          if (migratedData['migrated'] == true) migrationCount++;
          
        } catch (e) {
          errorCount++;
          debugPrint("Erreur parsing appareil $i: $e");
          // Continuer avec les autres appareils malgré l'erreur
        }
      }

      debugPrint("Chargement WiFi: ${loadedControls.length} appareils, "
                 "$migrationCount migrés, $errorCount erreurs");

      return LoadResult(
        data: loadedControls,
        itemsLoaded: loadedControls.length,
        migrationsApplied: migrationCount,
        errorsCount: errorCount,
        timestamp: DateTime.now(),
      );

    } catch (e, stackTrace) {
      debugPrint("Erreur critique lors du chargement WiFi: $e");
      debugPrint("Stack trace: $stackTrace");
      
      return LoadResult(
        data: [],
        error: e.toString(),
        timestamp: DateTime.now(),
      );
    }
  }

  // Migration des données depuis les anciennes versions
  Map<String, dynamic> _migrateData(Map<String, dynamic> data, int savedVersion) {
    final migratedData = Map<String, dynamic>.from(data);
    migratedData['migrated'] = false;

    // Migration depuis la version 1 (sans ID)
    if (savedVersion < 2) {
      if (!migratedData.containsKey('id')) {
        migratedData['id'] = null; // Será généré plus tard
      }
      migratedData['migrated'] = true;
    }

    return migratedData;
  }

  // Parsing robuste des données d'icône
  IconData _parseIconData(Map<String, dynamic> data) {
    try {
      final int? iconCodePoint = data['iconCodePoint'];
      final String? fontFamily = data['iconFontFamily'];
      
      if (iconCodePoint != null) {
        return IconData(
          iconCodePoint, 
          fontFamily: fontFamily ?? 'MaterialIcons'
        );
      }
    } catch (e) {
      debugPrint("Erreur parsing icône: $e");
    }
    
    // Icônes par défaut selon le type d'appareil
    final String name = (data['name'] as String? ?? '').toLowerCase();
    if (name.contains('led') || name.contains('lampe') || name.contains('light')) {
      return Icons.lightbulb_outline;
    } else if (name.contains('fan') || name.contains('ventilateur') || name.contains('air')) {
      return Icons.air;
    } else if (name.contains('temp') || name.contains('chauff')) {
      return Icons.thermostat;
    } else if (name.contains('motor') || name.contains('moteur')) {
      return Icons.electric_bolt;
    } else if (name.contains('gas') || name.contains('gaz')) {
      return Icons.local_fire_department;
    }
    
    return Icons.device_unknown;
  }

  // Méthode utilitaire pour effacer toutes les données
  Future<bool> clearAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_wifiControlsKey);
      await prefs.remove(_versionKey);
      return true;
    } catch (e) {
      debugPrint("Erreur effacement données WiFi: $e");
      return false;
    }
  }

  // Méthode pour obtenir des statistiques
  Future<StorageStats> getStorageStats() async {
    final prefs = await SharedPreferences.getInstance();
    final controlsJson = prefs.getStringList(_wifiControlsKey);
    final version = prefs.getInt(_versionKey) ?? 1;
    
    return StorageStats(
      itemsCount: controlsJson?.length ?? 0,
      dataVersion: version,
      lastUpdate: await _getLastModifiedTime(prefs),
    );
  }

  Future<DateTime?> _getLastModifiedTime(SharedPreferences prefs) async {
    // Implémentation basique - pourrait être améliorée avec un timestamp dédié
    try {
      final controlsJson = prefs.getStringList(_wifiControlsKey);
      if (controlsJson == null || controlsJson.isEmpty) return null;
      
      // Prendre le timestamp du premier élément comme approximation
      final firstItem = json.decode(controlsJson.first);
      final createdAt = firstItem['createdAt'] as int?;
      return createdAt != null ? DateTime.fromMillisecondsSinceEpoch(createdAt) : null;
    } catch (e) {
      return null;
    }
  }
}

// Classes de résultat pour une meilleure gestion des états
class SaveResult {
  final bool success;
  final int? itemsSaved;
  final String? error;
  final DateTime timestamp;

  SaveResult({
    required this.success,
    this.itemsSaved,
    this.error,
    required this.timestamp,
  });
}

class LoadResult<T> {
  final T data;
  final int? itemsLoaded;
  final int? migrationsApplied;
  final int? errorsCount;
  final bool isEmpty;
  final String? error;
  final DateTime timestamp;

  LoadResult({
    required this.data,
    this.itemsLoaded,
    this.migrationsApplied,
    this.errorsCount,
    this.isEmpty = false,
    this.error,
    required this.timestamp,
  });
}

class StorageStats {
  final int itemsCount;
  final int dataVersion;
  final DateTime? lastUpdate;

  StorageStats({
    required this.itemsCount,
    required this.dataVersion,
    this.lastUpdate,
  });
}

// Extension pour faciliter l'utilisation dans le widget WiFi
extension DataSaver2Extensions on DataSaver2 {
  // Chargement avec fallback automatique sur les appareils par défaut
  Future<List<DeviceControl>> loadControlsWithFallback(List<DeviceControl> defaultControls) async {
    final result = await loadControls();
    
    if (result.data.isEmpty || result.error != null) {
      debugPrint("Utilisation des contrôles par défaut");
      // Sauvegarder les defaults pour la prochaine fois
      await saveControls(defaultControls);
      return defaultControls;
    }
    
    return result.data;
  }

  // Sauvegarde incrémentale d'un seul appareil
  Future<SaveResult> saveSingleControl(DeviceControl control, List<DeviceControl> existingControls) async {
    final updatedControls = List<DeviceControl>.from(existingControls);
    final index = updatedControls.indexWhere((c) => c.id == control.id);
    
    if (index != -1) {
      updatedControls[index] = control;
    } else {
      // Générer un ID si manquant (comme dans Bluetooth)
      final newControl = DeviceControl(
        id: control.id ?? DateTime.now().millisecondsSinceEpoch,
        name: control.name,
        onCommand: control.onCommand,
        offCommand: control.offCommand,
        icon: control.icon,
        isActive: control.isActive,
      );
      updatedControls.add(newControl);
    }
    
    return await saveControls(updatedControls);
  }
}