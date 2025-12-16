// server_back.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ServerBack {
  static String baseUrl = 'https://claude-iot.onrender.com';
  static String? customBaseUrl;
  
  // Récupérer l'URL active (custom ou par défaut)
  static String get activeBaseUrl => customBaseUrl ?? baseUrl;
  
  // Vérifier la connexion au serveur
  static Future<Map<String, dynamic>> checkServerStatus() async {
    try {
      final response = await http.get(
        Uri.parse('${activeBaseUrl}/status'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'data': data,
          'message': 'Connecté au serveur avec succès'
        };
      } else {
        return {
          'success': false,
          'message': 'Erreur de connexion au serveur (${response.statusCode})'
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Impossible de se connecter au serveur: $e'
      };
    }
  }
  
  // Envoyer une commande au serveur
  static Future<Map<String, dynamic>> sendCommand(String command) async {
    try {
      final response = await http.post(
        Uri.parse('${activeBaseUrl}/commande_post'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'command': command}),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'data': data,
          'message': 'Commande envoyée avec succès'
        };
      } else {
        return {
          'success': false,
          'message': 'Erreur lors de l\'envoi de la commande (${response.statusCode})'
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Erreur de connexion: $e'
      };
    }
  }
  
  // Récupérer les messages (2 derniers)
  // server_back.dart
// Récupérer les messages (2 derniers)
static Future<Map<String, dynamic>> getMessages() async {
  try {
    final response = await http.get(
      // CHANGEMENT ICI : /smessage -> /messages
      Uri.parse('${activeBaseUrl}/messages'), // ← CORRECTION
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      List<dynamic> messages = data['messages'] ?? [];
      
      // Prendre seulement les 2 derniers messages
      List<dynamic> lastTwoMessages = [];
      if (messages.length >= 2) {
        lastTwoMessages = messages.sublist(0, 2);
      } else if (messages.isNotEmpty) {
        lastTwoMessages = messages;
      }
      
      return {
        'success': true,
        'messages': lastTwoMessages,
        'allMessages': messages,
        'count': lastTwoMessages.length
      };
    } else {
      return {
        'success': false,
        'message': 'Erreur lors de la récupération des messages'
      };
    }
  } catch (e) {
    return {
      'success': false,
      'message': 'Erreur de connexion: $e'
    };
  }
}
  
  // Définir une URL personnalisée
  static void setCustomBaseUrl(String url) {
    // Nettoyer l'URL
    String cleanedUrl = url.trim();
    if (cleanedUrl.endsWith('/')) {
      cleanedUrl = cleanedUrl.substring(0, cleanedUrl.length - 1);
    }
    customBaseUrl = cleanedUrl;
  }
  
  // Réinitialiser à l'URL par défaut
  static void resetToDefault() {
    customBaseUrl = null;
  }
  
  // Vérifier si on utilise l'URL par défaut
  static bool get isUsingDefaultUrl => customBaseUrl == null;
}