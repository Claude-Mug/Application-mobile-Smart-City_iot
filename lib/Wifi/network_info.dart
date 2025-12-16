import 'package:network_info_plus/network_info_plus.dart';

class NetworkInfoService {
  final NetworkInfo _networkInfo = NetworkInfo();

  Future<String?> getLocalIp() async {
    return _networkInfo.getWifiIP();
  }

  Future<String?> getGateway() async {
    return _networkInfo.getWifiGatewayIP();
  }
}