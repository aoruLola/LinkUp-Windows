import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:LinkUp/utils/LogUtil.dart';

/// 网络工具类，用于检测当前是否存在可用网络环境
class NetworkUtil {
  static final Connectivity _connectivity = Connectivity();

  /// 检查是否存在可用于校园网认证的网络环境
  /// Windows 桌面端通常也会通过以太网接入
  static Future<bool> isNetworkEnvironmentAvailable() async {
    try {
      final List<ConnectivityResult> results = await _connectivity.checkConnectivity();
      
      for (final result in results) {
        if (result == ConnectivityResult.wifi ||
            result == ConnectivityResult.ethernet) {
          return true;
        }
      }
      return false;
    } catch (e) {
      LogUtil.error('检测网络环境失败', e);
      return false;
    }
  }

  /// 获取当前网络连接类型
  static Future<String> getConnectionType() async {
    try {
      final List<ConnectivityResult> results = await _connectivity.checkConnectivity();
      
      if (results.isEmpty) {
        return '无网络连接';
      }
      
      if (results.contains(ConnectivityResult.wifi)) {
        return 'WiFi';
      }
      if (results.contains(ConnectivityResult.ethernet)) {
        return '以太网';
      }

      final result = results.first;
      switch (result) {
        case ConnectivityResult.mobile:
          return '移动数据';
        case ConnectivityResult.vpn:
          return 'VPN';
        case ConnectivityResult.bluetooth:
          return '蓝牙';
        case ConnectivityResult.other:
          return '其他网络';
        case ConnectivityResult.none:
          return '无网络连接';
        case ConnectivityResult.wifi:
          return 'WiFi';
        case ConnectivityResult.ethernet:
          return '以太网';
      }
    } catch (e) {
      return '未知';
    }
  }

  /// 监听网络状态变化
  static Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged;
  }
}
