import 'dart:async';
import 'package:claude_iot/Wifi/http.dart';
import 'package:claude_iot/Wifi/connectivity.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionManager {
  final HttpService _httpService;
  final ConnectivityService _connectivityService;
  
  // États de connexion
  bool _isConnected = false;
  bool _autoConnectEnabled = true;
  bool _isAttemptingReconnect = false;
  
  // Timer et abonnements
  Timer? _reconnectTimer;
  StreamSubscription? _connectivitySubscription;
  
  // Callbacks pour la mise à jour de l'UI
  final Function(bool) onConnectionStatusChanged;
  final Function(String) onLogMessage;
  final Function() onReconnectStarted;
  final Function(String, int) onReconnectSuccess;
  final Function(String) onReconnectFailed;
  
  ConnectionManager({
    required this.onConnectionStatusChanged,
    required this.onLogMessage,
    required this.onReconnectStarted,
    required this.onReconnectSuccess,
    required this.onReconnectFailed,
    HttpService? httpService,
    ConnectivityService? connectivityService,
  }) : 
        _httpService = httpService ?? HttpService(),
        _connectivityService = connectivityService ?? ConnectivityService();
  
  // Initialiser le gestionnaire de connexion
  Future<void> initialize() async {
    await _loadSavedSettings();
    _setupConnectivityListener();
    
    // Tenter une reconnexion automatique après un court délai
    await Future.delayed(const Duration(seconds: 2));
    await _attemptAutoReconnect();
  }
  
  // Charger les paramètres sauvegardés
  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _autoConnectEnabled = prefs.getBool('autoConnectEnabled') ?? true;
    
    onLogMessage('>> Paramètres chargés: auto-reconnect $_autoConnectEnabled');
  }
  
  // Configurer l'écouteur de connectivité
  void _setupConnectivityListener() {
    _connectivitySubscription = _connectivityService.connectionStream.listen(
      _handleConnectivityChange,
    );
  }
  
  // Gérer les changements de connectivité
  void _handleConnectivityChange(List<ConnectivityResult> status) {
    final isNetworkAvailable = status.contains(ConnectivityResult.wifi) ||
        status.contains(ConnectivityResult.mobile) ||
        status.contains(ConnectivityResult.ethernet);
    
    onLogMessage('>> État réseau: ${status.map((e) => e.toString().split('.').last).join(', ')}');
    
    if (!isNetworkAvailable) {
      _handleNetworkLost();
    } else {
      _handleNetworkRegained();
    }
  }
  
  // Gérer la perte de réseau
  void _handleNetworkLost() {
    _isConnected = false;
    _httpService.stopPolling();
    
    onConnectionStatusChanged(false);
    onLogMessage('>> Connexion réseau perdue');
  }
  
  // Gérer le retour du réseau
  void _handleNetworkRegained() {
    onLogMessage('>> Réseau retrouvé - vérification de la connexion...');
    
    if (_autoConnectEnabled && !_isConnected) {
      _scheduleReconnect();
    }
  }
  
  // Tenter la reconnexion automatique
  Future<void> _attemptAutoReconnect() async {
    if (!_autoConnectEnabled) return;
    
    final prefs = await SharedPreferences.getInstance();
    final wasConnected = prefs.getBool('wasConnected') ?? false;
    final lastIP = prefs.getString('lastConnectedIP');
    final lastPort = prefs.getInt('lastConnectedPort');
    
    if (wasConnected && lastIP != null && lastPort != null) {
      onLogMessage('>> Tentative de reconnexion automatique...');
      _isAttemptingReconnect = true;
      onReconnectStarted();
      
      await _testAndReconnect(lastIP, lastPort);
    }
  }
  
  // Planifier une reconnexion
  void _scheduleReconnect() {
    if (!_autoConnectEnabled || _isAttemptingReconnect) return;
    
    _isAttemptingReconnect = true;
    onLogMessage('>> Reconnexion automatique dans 5 secondes...');
    onReconnectStarted();
    
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isConnected && _autoConnectEnabled) {
        _attemptAutoReconnect();
      }
    });
  }
  
  // Tester et rétablir la connexion
  Future<bool> _testAndReconnect(String ip, int port) async {
    // Vérifier la connectivité réseau
    final currentConnections = await _connectivityService.getCurrentConnection();
    if (currentConnections.contains(ConnectivityResult.none)) {
      onLogMessage('>> Erreur: Aucune connexion réseau active');
      return false;
    }
    
    // Tester la connexion à l'ESP
    final result = await _httpService.testConnection(ip: ip, port: port);
    
    if (result.success) {
      _handleConnectionSuccess(ip, port);
      return true;
    } else {
      _handleConnectionFailure(result.message);
      return false;
    }
  }
  
  // Gérer le succès de connexion
void _handleConnectionSuccess(String ip, int port) {
  _isConnected = true;
  _isAttemptingReconnect = false;
  _reconnectTimer?.cancel();
  
  onConnectionStatusChanged(true);
  onLogMessage('>> Connexion rétablie avec $ip:$port');
  onReconnectSuccess(ip, port);
  
  _saveConnectionState(true);
  _saveConnectionInfo(ip, port);
}
  
  // Gérer l'échec de connexion
  void _handleConnectionFailure(String errorMessage) {
    _isConnected = false;
    _isAttemptingReconnect = false;
    
    onConnectionStatusChanged(false);
    onLogMessage('>> Échec de reconnexion: $errorMessage');
    onReconnectFailed(errorMessage);
    
    // Rescheduler une reconnexion si activé
    if (_autoConnectEnabled) {
      _scheduleReconnect();
    }
  }
  
  // Méthode pour démarrer une connexion manuelle
  Future<bool> connect(String ip, int port) async {
    return await _testAndReconnect(ip, port);
  }
  
  // Sauvegarder l'état de connexion
  Future<void> _saveConnectionState(bool connected) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wasConnected', connected);
  }
  
  // Sauvegarder les informations de connexion
  Future<void> _saveConnectionInfo(String ip, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastConnectedIP', ip);
    await prefs.setInt('lastConnectedPort', port);
    await prefs.setBool('autoConnectEnabled', _autoConnectEnabled);
  }
  
  // Activer/désactiver la reconnexion automatique
  Future<void> setAutoReconnect(bool enabled) async {
    _autoConnectEnabled = enabled;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoConnectEnabled', enabled);
    
    if (!enabled) {
      _reconnectTimer?.cancel();
      _isAttemptingReconnect = false;
    }
    
    onLogMessage('>> Reconnexion automatique: ${enabled ? "activée" : "désactivée"}');
  }
  
  // Obtenir l'état de connexion actuel
  bool get isConnected => _isConnected;
  bool get isAttemptingReconnect => _isAttemptingReconnect;
  bool get autoConnectEnabled => _autoConnectEnabled;
  
  // Nettoyer les ressources
  void dispose() {
    _reconnectTimer?.cancel();
    _connectivitySubscription?.cancel();
  }
  
  // Méthode pour gérer la reprise de l'application
  void onAppResumed() {
    onLogMessage('>> Application reprise - vérification connexion...');
    
    if (_autoConnectEnabled && !_isConnected) {
      _attemptAutoReconnect();
    }
  }
}