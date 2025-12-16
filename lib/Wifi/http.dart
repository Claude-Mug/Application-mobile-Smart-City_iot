import 'package:http/http.dart' as http;
import 'dart:async';

class HttpService {
  // Un StreamController pour diffuser les résultats du polling
  final StreamController<({bool success, String message})> _pollingController =
      StreamController<({bool success, String message})>.broadcast();
  Stream<({bool success, String message})> get pollingMessages => _pollingController.stream;

  // Un Timer pour gérer l'intervalle de polling
  Timer? _pollingTimer;

  // Méthode existante pour envoyer une commande et obtenir une réponse unique
  // Elle peut être utilisée pour des demandes ponctuelles d'informations
  Future<({bool success, String message})> sendCommand({
    required String ip,
    required int port,
    required String command, // La commande peut être une requête de données, ex: "getTemp"
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      // Validation des paramètres
      if (!_isValidIp(ip)) {
        return (success: false, message: "Adresse IP invalide");
      }
      
      if (port <= 0 || port > 65535) {
        return (success: false, message: "Port invalide");
      }

      final response = await http.get(
        Uri.parse('http://$ip:$port/$command'),
      ).timeout(timeout, onTimeout: () {
        return http.Response('Timeout', 408);
      });

      if (response.statusCode == 200) {
        return (success: true, message: response.body); // Retourne le corps de la réponse comme message
      } else {
        return (
          success: false, 
          message: "Erreur HTTP ${response.statusCode}: ${response.body}"
        );
      }
    } on http.ClientException catch (e) {
      return (success: false, message: "Erreur réseau: ${e.message}");
    } on TimeoutException {
      return (success: false, message: "Timeout de connexion");
    } catch (e) {
      return (success: false, message: "Erreur inattendue: ${e.toString()}");
    }
  }

  // Nouvelle méthode pour démarrer le polling (récupération d'infos toutes les X secondes)
  void startPolling({
    required String ip,
    required int port,
    required String command, // La commande à envoyer à chaque intervalle, ex: "getSensorData"
    required Duration interval, // L'intervalle de polling, ex: Duration(seconds: 3)
    Duration timeout = const Duration(seconds: 3),
  }) {
    stopPolling(); // Arrête tout polling précédent avant d'en démarrer un nouveau

    _pollingTimer = Timer.periodic(interval, (timer) async {
      final result = await sendCommand(
        ip: ip,
        port: port,
        command: command,
        timeout: timeout,
      );
      _pollingController.add(result); // Diffuse le résultat à tous les auditeurs
    });
    print('HTTP Polling démarré pour http://$ip:$port/$command toutes les ${interval.inSeconds}s');
  }

  // Méthode pour arrêter le polling
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    print('HTTP Polling arrêté.');
  }

  // Nouvelle méthode pour le test de connexion HTTP de base
  Future<({bool success, String message})> testConnection({
    required String ip,
    required int port,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      if (!_isValidIp(ip)) {
        return (success: false, message: "Adresse IP invalide");
      }
      if (port <= 0 || port > 65535) {
        return (success: false, message: "Port invalide");
      }

      // Tente de faire une simple requête HEAD ou GET à la racine pour tester la connectivité
      final response = await http.get(Uri.parse('http://$ip:$port/'),
      ).timeout(timeout, onTimeout: () {
        return http.Response('Timeout', 408); // Code de timeout HTTP
      });

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (success: true, message: "Connexion HTTP OK");
      } else {
        return (success: false, message: "Erreur HTTP: ${response.statusCode}");
      }
    } on http.ClientException catch (e) {
      return (success: false, message: "Erreur réseau: ${e.message}");
    } on TimeoutException {
      return (success: false, message: "Timeout de connexion");
    } catch (e) {
      return (success: false, message: "Erreur inattendue: ${e.toString()}");
    }
  }

  bool _isValidIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    
    for (var part in parts) {
      final int? value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) {
        return false;
      }
    }
    return true;
  }

  // N'oubliez pas de disposer du StreamController lorsque le service n'est plus nécessaire
  void dispose() {
    stopPolling();
    _pollingController.close();
  }
}