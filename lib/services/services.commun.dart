// lib/services/Services.Wifi.dart - VERSION AMÉLIORÉE
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

import '../Wifi/connectivity.dart';
import '../Wifi/network_info.dart';
import '../Wifi/http.dart';
import '../Wifi/websocket.dart';

enum CommunicationMode { wifi, bluetooth }

enum WiFiProtocol {
  http,
  websocket,
  none,
}

// Type de microcontrôleur détecté
enum MicrocontrollerType {
  direct,      // WiFi.h + WiFiServer (commandes directes: /COMMANDE)
  parameter,   // WebServer.h (commandes paramétrées: /cmd?c=COMMANDE)
  auto,        // Détection automatique
  unknown
}

class WiFiCommunicationManager {
  final ConnectivityService _connectivityService = ConnectivityService();
  final NetworkInfoService _networkInfoService = NetworkInfoService();
  final HttpService _httpService = HttpService();
  final WebSocketService _webSocketService = WebSocketService();
  

  WiFiProtocol _activeProtocol = WiFiProtocol.none;
  String? _currentIpAddress;
  MicrocontrollerType _microcontrollerType = MicrocontrollerType.auto;
  
  // Cache pour mémoriser le type détecté par IP
  final Map<String, MicrocontrollerType> _typeCache = {};

  Stream<List<ConnectivityResult>> get wifiConnectivityStream => _connectivityService.connectionStream;
  Stream<({bool success, String message})> get httpPollingMessages => _httpService.pollingMessages;
  Stream<String> get webSocketMessages => _webSocketService.messages;
  Stream<bool> get isWebSocketConnected => _webSocketService.isConnected;

  WiFiCommunicationManager() {
    _connectivityService.connectionStream.listen((status) {
      if (!status.contains(ConnectivityResult.wifi)) {
        disconnectAllWifiConnections();
        print('WiFiCommunicationManager: Wi-Fi perdu. Déconnexion de toutes les connexions.');
      }
    });
  }

  Future<void> initialize() async {
    // Initialisation des services
  }

  void setActiveProtocol(WiFiProtocol protocol) {
    _activeProtocol = protocol;
    print('WiFiCommunicationManager: Protocole actif défini sur: $_activeProtocol.');
  }

  WiFiProtocol getActiveProtocol() => _activeProtocol;

  /// Définit le type de microcontrôleur manuellement
  void setMicrocontrollerType(MicrocontrollerType type) {
    _microcontrollerType = type;
    print('WiFiCommunicationManager: Type microcontrôleur défini sur: $type');
  }

  // --- Méthodes de connectivité de base ---
  Future<bool> isWifiConnected() async {
    return await _connectivityService.isWifiConnected();
  }

  Future<List<ConnectivityResult>> getCurrentConnection() async {
    return await _connectivityService.getCurrentConnection();
  }

  Future<String?> getLocalIp() async {
    return await _networkInfoService.getLocalIp();
  }

  Future<String?> getGateway() async {
    return await _networkInfoService.getGateway();
  }

  // --- Méthode HTTP adaptative améliorée ---
  Future<({bool success, String message})> sendHttpCommand({
    required String ip,
    required int port,
    required String command,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final connectivityResults = await _connectivityService.getCurrentConnection();
    bool isConnected = connectivityResults.isNotEmpty && !connectivityResults.contains(ConnectivityResult.none);

    if (!isConnected) {
      return (success: false, message: 'Aucune connexion réseau détectée');
    }

    setActiveProtocol(WiFiProtocol.http);
    _currentIpAddress = ip;

    try {
      // Clé de cache pour cette IP
      final cacheKey = '$ip:$port';
      
      // Détection automatique si nécessaire
      if (_microcontrollerType == MicrocontrollerType.auto && !_typeCache.containsKey(cacheKey)) {
        await _detectMicrocontrollerType(ip, port, timeout);
      }

      final effectiveType = _typeCache[cacheKey] ?? _microcontrollerType;

      switch (effectiveType) {
        case MicrocontrollerType.direct:
          return await _sendDirectCommand(ip, port, command, timeout);
        
        case MicrocontrollerType.parameter:
          return await _sendParameterCommand(ip, port, command, timeout);
        
        case MicrocontrollerType.auto:
        case MicrocontrollerType.unknown:
        default:
          // Essai séquentiel des deux formats
          return await _tryBothCommandFormats(ip, port, command, timeout);
      }
    } catch (e) {
      return (success: false, message: 'Erreur lors de l\'envoi HTTP: ${e.toString()}');
    }
  }

  /// Détection automatique du type de microcontrôleur
  Future<void> _detectMicrocontrollerType(String ip, int port, Duration timeout) async {
    final cacheKey = '$ip:$port';
    
    print('🔍 Détection du type de microcontrôleur pour $ip:$port...');

    // Test avec une commande simple
    const testCommand = 'test';
    
    final directResult = await _sendDirectCommand(ip, port, testCommand, timeout);
    final paramResult = await _sendParameterCommand(ip, port, testCommand, timeout);

    // Analyse des résultats
    if (directResult.success && !paramResult.success) {
      _typeCache[cacheKey] = MicrocontrollerType.direct;
      print('✅ Type détecté: DIRECT (WiFi.h + WiFiServer)');
    } else if (paramResult.success && !directResult.success) {
      _typeCache[cacheKey] = MicrocontrollerType.parameter;
      print('✅ Type détecté: PARAMÉTRÉ (WebServer.h)');
    } else if (directResult.success && paramResult.success) {
      // Les deux fonctionnent, priorité au direct (plus courant)
      _typeCache[cacheKey] = MicrocontrollerType.direct;
      print('✅ Type détecté: LES DEUX (priorité DIRECT)');
    } else {
      _typeCache[cacheKey] = MicrocontrollerType.unknown;
      print('❌ Type détecté: INCONNU (aucun format ne fonctionne)');
    }
  }

  /// Essai séquentiel des deux formats
  Future<({bool success, String message})> _tryBothCommandFormats(
      String ip, int port, String command, Duration timeout) async {
    
    print('🔄 Essai des deux formats de commande...');
    
    // Essai format direct d'abord
    final directResult = await _sendDirectCommand(ip, port, command, timeout);
    if (_isSuccessfulResponse(directResult)) {
      _typeCache['$ip:$port'] = MicrocontrollerType.direct;
      return directResult;
    }

    // Essai format paramétré
    final paramResult = await _sendParameterCommand(ip, port, command, timeout);
    if (_isSuccessfulResponse(paramResult)) {
      _typeCache['$ip:$port'] = MicrocontrollerType.parameter;
      return paramResult;
    }

    // Les deux ont échoué, retourner le résultat le plus prometteur
    return directResult.message.contains('404') ? paramResult : directResult;
  }

  /// Vérifie si une réponse est considérée comme réussie
  bool _isSuccessfulResponse(({bool success, String message}) response) {
    return response.success || 
           response.message.contains('200') ||
           (response.message.contains('ESP32') && !response.message.contains('404'));
  }

  /// Envoi en format direct (WiFi.h + WiFiServer)
  Future<({bool success, String message})> _sendDirectCommand(
      String ip, int port, String command, Duration timeout) async {
    try {
      final url = Uri.parse('http://$ip:$port/$command');
      final response = await http.get(url).timeout(timeout);
      
      return (
        success: response.statusCode == 200,
        message: 'HTTP ${response.statusCode}: ${response.body}'
      );
    } catch (e) {
      return (success: false, message: 'Format direct échoué: $e');
    }
  }

  /// Envoi en format paramétré (WebServer.h)
  Future<({bool success, String message})> _sendParameterCommand(
      String ip, int port, String command, Duration timeout) async {
    try {
      final url = Uri.parse('http://$ip:$port/cmd?c=${Uri.encodeComponent(command)}');
      final response = await http.get(url).timeout(timeout);
      
      return (
        success: response.statusCode == 200,
        message: 'HTTP ${response.statusCode}: ${response.body}'
      );
    } catch (e) {
      return (success: false, message: 'Format paramétré échoué: $e');
    }
  }

  // --- Autres méthodes existantes (polling, WebSocket) ---
  
  void startHttpPolling({
    required String ip,
    required int port,
    required String command,
    required Duration interval,
    Duration timeout = const Duration(seconds: 3),
  }) {
    _connectivityService.isWifiConnected().then((connected) {
      if (connected) {
        setActiveProtocol(WiFiProtocol.http);
        _currentIpAddress = ip;
        _httpService.startPolling(ip: ip, port: port, command: command, interval: interval, timeout: timeout);
      } else {
        print('WiFiCommunicationManager: Impossible de démarrer le polling HTTP, le Wi-Fi n\'est pas connecté.');
      }
    });
  }

  void stopPolling() {
    _httpService.stopPolling();
  }

  Future<bool> connectWebSocket(String ip, {int port = 81}) async {
    if (!await isWifiConnected()) {
      print('WiFiCommunicationManager: Impossible de se connecter, le Wi-Fi n\'est pas connecté.');
      return false;
    }

    setActiveProtocol(WiFiProtocol.websocket);
    _webSocketService.setWebSocketPort(port);
    _currentIpAddress = ip;
    return await _webSocketService.connect(ip);
  }

  void sendWebSocketMessage(String message) {
    if (_activeProtocol == WiFiProtocol.websocket && _webSocketService.currentIsConnected) {
      _webSocketService.sendMessage(message);
    } else {
      print('WiFiCommunicationManager: Impossible d\'envoyer un message WebSocket.');
    }
  }

  void disconnectWebSocket() {
    _webSocketService.disconnect();
  }

  void disconnectAllWifiConnections() {
    print('WiFiCommunicationManager: Déconnexion de toutes les connexions Wi-Fi actives.');
    _httpService.stopPolling();
    _webSocketService.disconnect();
    _activeProtocol = WiFiProtocol.none;
    _currentIpAddress = null;
    _typeCache.clear(); // Vider le cache à la déconnexion
  }

  void dispose() {
    _httpService.dispose();
    _webSocketService.dispose();
  }
}


