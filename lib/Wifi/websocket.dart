// lib/Wifi/websocket.dart
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'dart:async';

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  Stream<String> get messages => _messageController.stream;

  // Nouvelle variable pour stocker l'état de connexion actuel
  bool _currentIsConnected = false;

  // Stream public pour l'état de la connexion (pour les listeners externes)
  final StreamController<bool> _isConnectedController = StreamController<bool>.broadcast();
  Stream<bool> get isConnected => _isConnectedController.stream;

  // Getter pour obtenir l'état de connexion actuel de manière synchrone
  bool get currentIsConnected => _currentIsConnected;


  int _webSocketPort = 81; // Port typique pour les WebSockets sur ESP, à adapter

  void setWebSocketPort(int port) {
    _webSocketPort = port;
  }

  Future<bool> connect(String ip) async {
    if (ip.isEmpty) {
      _messageController.add('[Erreur: IP vide pour WebSocket]');
      _currentIsConnected = false; // Mettre à jour l'état interne
      _isConnectedController.add(false); // Diffuser l'état aux abonnés
      return false;
    }

    disconnect(); // Assurez-vous de fermer toute connexion précédente

    try {
      final wsUrl = 'ws://$ip:$_webSocketPort/';
      _channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));

      _channel!.stream.listen(
        (message) {
          _messageController.add(message.toString());
          print('WebSocket: Reçu: ${message.toString()}');
        },
        onDone: () {
          print('WebSocket: Déconnecté.');
          _messageController.add('[Déconnecté]');
          _currentIsConnected = false; // Mettre à jour l'état interne
          _isConnectedController.add(false); // Diffuser l'état
        },
        onError: (error) {
          print('WebSocket: Erreur: $error');
          _messageController.add('[Erreur WebSocket: $error]');
          _currentIsConnected = false; // Mettre à jour l'état interne
          _isConnectedController.add(false); // Diffuser l'état
          disconnect(); // Fermer la connexion en cas d'erreur
        },
        cancelOnError: true,
      );

      // Pour l'établissement initial, on assume un succès si pas d'erreur immédiate
      // Il est important de laisser un court délai pour que la connexion s'établisse réellement
      await Future.delayed(Duration(milliseconds: 500)); // Laissez ce délai
      _currentIsConnected = true; // Mettre à jour l'état interne
      _isConnectedController.add(true); // Diffuser l'état
      _messageController.add('[Connecté à $wsUrl]');
      print('WebSocket: Tentative de connexion à $wsUrl');
      return true;

    } catch (e) {
      print('WebSocket: Échec de connexion: $e');
      _messageController.add('[Échec connexion WebSocket: $e]');
      _currentIsConnected = false; // Mettre à jour l'état interne
      _isConnectedController.add(false); // Diffuser l'état
      return false;
    }
  }

  void sendMessage(String message) {
    // Utiliser la variable interne _currentIsConnected
    if (_channel != null && _channel!.sink != null && _currentIsConnected) {
      _channel!.sink.add(message);
      print('WebSocket: Envoyé: $message');
    } else {
      print('WebSocket: Non connecté, impossible d\'envoyer le message: $message');
    }
  }

  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
      _currentIsConnected = false; // Mettre à jour l'état interne
      _isConnectedController.add(false); // Diffuser l'état
      print('WebSocket: Déconnexion forcée.');
    }
  }

  void dispose() {
    _messageController.close();
    _isConnectedController.close();
    disconnect();
  }
}