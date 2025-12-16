// command_settings.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

enum TextTransform {
  lowercase,
  uppercase,
  capitalize,
  normal
}

enum SpaceReplacement {
  underscore,
  dash,
  none,
  space
}

class CommandSettings {
  final TextTransform textTransform;
  final SpaceReplacement spaceReplacement;
  final bool removeAccents;
  final bool removeSpecialChars;
  final bool addPrefix;
  final String customPrefix;

  CommandSettings({
    this.textTransform = TextTransform.lowercase,
    this.spaceReplacement = SpaceReplacement.underscore,
    this.removeAccents = true,
    this.removeSpecialChars = true,
    this.addPrefix = false,
    this.customPrefix = "cmd_",
  });

  Map<String, dynamic> toMap() {
    return {
      'textTransform': textTransform.index,
      'spaceReplacement': spaceReplacement.index,
      'removeAccents': removeAccents,
      'removeSpecialChars': removeSpecialChars,
      'addPrefix': addPrefix,
      'customPrefix': customPrefix,
    };
  }

  factory CommandSettings.fromMap(Map<String, dynamic> map) {
    return CommandSettings(
      textTransform: TextTransform.values[map['textTransform']],
      spaceReplacement: SpaceReplacement.values[map['spaceReplacement']],
      removeAccents: map['removeAccents'] ?? true,
      removeSpecialChars: map['removeSpecialChars'] ?? true,
      addPrefix: map['addPrefix'] ?? false,
      customPrefix: map['customPrefix'] ?? "cmd_",
    );
  }

  CommandSettings copyWith({
    TextTransform? textTransform,
    SpaceReplacement? spaceReplacement,
    bool? removeAccents,
    bool? removeSpecialChars,
    bool? addPrefix,
    String? customPrefix,
  }) {
    return CommandSettings(
      textTransform: textTransform ?? this.textTransform,
      spaceReplacement: spaceReplacement ?? this.spaceReplacement,
      removeAccents: removeAccents ?? this.removeAccents,
      removeSpecialChars: removeSpecialChars ?? this.removeSpecialChars,
      addPrefix: addPrefix ?? this.addPrefix,
      customPrefix: customPrefix ?? this.customPrefix,
    );
  }
}

class CommandSettingsManager {
  static const String _storageKey = 'command_settings';

  Future<CommandSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final String? settingsJson = prefs.getString(_storageKey);
    
    if (settingsJson != null) {
      final Map<String, dynamic> map = json.decode(settingsJson);
      return CommandSettings.fromMap(map);
    }
    
    return CommandSettings(); // Retourne les paramètres par défaut
  }

  Future<void> saveSettings(CommandSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final String settingsJson = json.encode(settings.toMap());
    await prefs.setString(_storageKey, settingsJson);
  }
}

// Méthode de normalisation qui utilise les paramètres
String normalizeCommandWithSettings(String command, CommandSettings settings) {
  String normalized = command;

  // Supprimer les accents si activé
  if (settings.removeAccents) {
    normalized = normalized
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[àâä]'), 'a')
      .replaceAll(RegExp(r'[îï]'), 'i')
      .replaceAll(RegExp(r'[ôö]'), 'o')
      .replaceAll(RegExp(r'[ùûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c');
  }

  // Supprimer les caractères spéciaux si activé
  if (settings.removeSpecialChars) {
    normalized = normalized.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), '');
  }

  // Appliquer la transformation de texte
  switch (settings.textTransform) {
    case TextTransform.lowercase:
      normalized = normalized.toLowerCase();
      break;
    case TextTransform.uppercase:
      normalized = normalized.toUpperCase();
      break;
    case TextTransform.capitalize:
      normalized = _capitalizeWords(normalized);
      break;
    case TextTransform.normal:
      // Ne rien faire, garder la casse originale
      break;
  }

  // Gérer le remplacement des espaces
  switch (settings.spaceReplacement) {
    case SpaceReplacement.underscore:
      normalized = normalized.replaceAll(' ', '_');
      break;
    case SpaceReplacement.dash:
      normalized = normalized.replaceAll(' ', '-');
      break;
    case SpaceReplacement.none:
      normalized = normalized.replaceAll(' ', '');
      break;
    case SpaceReplacement.space:
      // Garder les espaces
      break;
  }

  // Ajouter un préfixe si activé
  if (settings.addPrefix && settings.customPrefix.isNotEmpty) {
    normalized = settings.customPrefix + normalized;
  }

  return normalized;
}

String _capitalizeWords(String text) {
  if (text.isEmpty) return text;
  
  return text.split(' ').map((word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }).join(' ');
}