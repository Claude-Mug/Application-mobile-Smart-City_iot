import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  bool _isChecking = false;
  

  Future<bool> isWifiConnected() async {
    if (_isChecking) return false;
    _isChecking = true;
    
    try {
      // Modifié pour gérer la List<ConnectivityResult>
      final status = await _connectivity.checkConnectivity();
      _isChecking = false;
      // Vérifie si la liste contient ConnectivityResult.wifi
      return status.contains(ConnectivityResult.wifi);
    } catch (e) {
      _isChecking = false;
      return false;
    }
  }

  // Modifié pour renvoyer un Stream<List<ConnectivityResult>>
  Stream<List<ConnectivityResult>> get connectionStream {
    return _connectivity.onConnectivityChanged.handleError((error) {
      // Retourne une liste vide ou gère l'erreur différemment si nécessaire
      return [ConnectivityResult.none];
    });
  }

  // Nouvelle méthode pour obtenir le type de connexion actuel
  // Modifié pour renvoyer Future<List<ConnectivityResult>>
  Future<List<ConnectivityResult>> getCurrentConnection() async {
    try {
      return await _connectivity.checkConnectivity();
    } catch (e) {
      return [ConnectivityResult.none];
    }
  }
}