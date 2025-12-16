// lib/Wifi/wifi_communication_manager.dart

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../Wifi/connectivity.dart'; 
import '../Wifi/network_info.dart';   
import '../Wifi/http.dart';            
import '../Wifi/websocket.dart';       

enum WiFiProtocol {
  http,
  websocket,
  none, // Pour indiquer qu'aucun protocole spécifique n'est actif
}

class WiFiControlManager {
  final ConnectivityService _connectivityService = ConnectivityService();
  final NetworkInfoService _networkInfoService = NetworkInfoService();
  final HttpService _httpService = HttpService();
  final WebSocketService _webSocketService = WebSocketService();

  WiFiProtocol _activeProtocol = WiFiProtocol.none;
  String? _currentIpAddress; // Pour stocker l'IP de l'appareil connecté

  // Stream pour notifier les changements de l'état global de la connexion Wi-Fi
  Stream<List<ConnectivityResult>> get wifiConnectivityStream => _connectivityService.connectionStream;

  // Stream pour les messages HTTP (polling)
  Stream<({bool success, String message})> get httpPollingMessages => _httpService.pollingMessages;

  // Stream pour les messages WebSocket
  Stream<String> get webSocketMessages => _webSocketService.messages;

  // Stream pour l'état de la connexion WebSocket
  Stream<bool> get isWebSocketConnected => _webSocketService.isConnected;

  WiFiControlManager() {
    // Écoute les changements de connectivité Wi-Fi
    _connectivityService.connectionStream.listen((status) {
      if (!status.contains(ConnectivityResult.wifi)) {
        // Si le Wi-Fi est perdu, déconnecte toutes les connexions Wi-Fi actives
        disconnectAllWifiConnections();
        print('WiFiControlManager: Wi-Fi perdu. Déconnexion de toutes les connexions.');
      }
    });
  }

  Future<void> initialize() async {
    // Aucune initialisation spécifique requise pour l'instant
    // Les services internes s'initialisent au besoin
  }

  /// Définit le protocole Wi-Fi actif pour les opérations.
  void setActiveProtocol(WiFiProtocol protocol) {
    _activeProtocol = protocol;
    print('WiFiControlManager: Protocole actif défini sur: $_activeProtocol.');
  }

  /// Récupère le protocole Wi-Fi actif.
  WiFiProtocol getActiveProtocol() => _activeProtocol;

  // --- Méthodes de connectivité Wi-Fi de base ---
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

  // --- Gestion HTTP ---

  /// Envoie une commande HTTP ponctuelle.
  // Dans lib/services/Services.Wifi.dart, à l'intérieur de la classe WiFiControlManager

Future<({bool success, String message})> sendHttpCommand({
  required String ip,
  required int port,
  required String command,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final connectivityResults = await _connectivityService.getCurrentConnection();

  bool isConnected = connectivityResults.isNotEmpty && !connectivityResults.contains(ConnectivityResult.none);

  if (!isConnected) {
    return (success: false, message: 'Aucune connexion réseau détectée pour la commande HTTP.');
  }

  setActiveProtocol(WiFiProtocol.http);
  _currentIpAddress = ip;

  try {
    // CORRECTION ICI : Retournez directement le résultat de sendCommand
    final response = await _httpService.sendCommand(ip: ip, port: port, command: command, timeout: timeout);
    return response; // `response` est déjà de type `({bool success, String message})`
  } catch (e) {
    return (success: false, message: 'Erreur lors de l\'envoi HTTP: ${e.toString()}');
  }
}

  /// Démarre le polling HTTP pour des mises à jour continues.
  void startHttpPolling({
    required String ip,
    required int port,
    required String command,
    required Duration interval,
    Duration timeout = const Duration(seconds: 3),
  }) {
    // Vérifie si le Wi-Fi est connecté avant de démarrer le polling
    _connectivityService.isWifiConnected().then((connected) {
      if (connected) {
        setActiveProtocol(WiFiProtocol.http);
        _currentIpAddress = ip; // Stocke l'IP de l'appareil HTTP
        _httpService.startPolling(ip: ip, port: port, command: command, interval: interval, timeout: timeout);
      } else {
        print('WiFiControlManager: Impossible de démarrer le polling HTTP, le Wi-Fi n\'est pas connecté.');
      }
    });
  }

  /// Arrête le polling HTTP.
  void stopPolling() { // Cette méthode est ajoutée pour exposer stopPolling de HttpService
    _httpService.stopPolling();
  }

  // --- Gestion WebSocket ---

  /// Tente de se connecter à un serveur WebSocket.
  Future<bool> connectWebSocket(String ip, {int port = 81}) async {
    // Vérifie si le Wi-Fi est connecté avant d'établir la connexion WebSocket
    if (!await isWifiConnected()) {
      print('WiFiControlManager: Impossible de se connecter, le Wi-Fi n\'est pas connecté.');
      return false;
    }

    setActiveProtocol(WiFiProtocol.websocket);
    _webSocketService.setWebSocketPort(port);
    _currentIpAddress = ip; // Stocke l'IP de l'appareil WebSocket
    return await _webSocketService.connect(ip);
  }

  /// Envoie un message via la connexion WebSocket active.
  void sendWebSocketMessage(String message) {
    if (_activeProtocol == WiFiProtocol.websocket && _webSocketService.currentIsConnected) {
      _webSocketService.sendMessage(message);
    } else {
      print('WiFiControlManager: Impossible d\'envoyer un message WebSocket. Le protocole n\'est pas actif ou WebSocket non connecté.');
    }
  }

  /// Déconnecte la connexion WebSocket.
  void disconnectWebSocket() {
    _webSocketService.disconnect();
    // On ne change pas le protocole actif ici, car l'utilisateur pourrait vouloir retenter
  }

  /// Déconnecte toutes les connexions Wi-Fi actives gérées par ce manager.
  void disconnectAllWifiConnections() {
    print('WiFiControlManager: Déconnexion de toutes les connexions Wi-Fi actives.');
    _httpService.stopPolling(); // Arrête le polling HTTP
    _webSocketService.disconnect(); // Déconnecte le WebSocket
    _activeProtocol = WiFiProtocol.none; // Réinitialise le protocole actif
    _currentIpAddress = null; // Efface l'IP de l'appareil connecté
  }

  /// Nettoyage des ressources.
  void dispose() {
    _httpService.dispose();
    _webSocketService.dispose();
    // Le service de connectivité n'a pas de dispose explicite nécessaire ici car il utilise des streams
  }
}