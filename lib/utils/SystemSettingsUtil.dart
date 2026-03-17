import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:LinkUp/utils/LogUtil.dart';

/// 系统设置工具类
class SystemSettingsUtil {
  static const String _keepAliveKey = 'keep_alive';
  static const String _autoStartKey = 'auto_start';
  static const MethodChannel _androidPlatform =
      MethodChannel('com.mel0ny.linkup/system');
  static const MethodChannel _windowsPlatform =
      MethodChannel('com.mel0ny.linkup/windows');
  
  static SharedPreferences? _prefs;
  static bool _isKeepAliveEnabled = false;
  static bool _windowsChannelReady = false;
  static final StreamController<void> _trayReconnectController =
      StreamController<void>.broadcast();

  static Stream<void> get onTrayReconnect => _trayReconnectController.stream;
  static bool get supportsDesktopTray => Platform.isWindows;
  static bool get supportsKeepAliveSetting =>
      Platform.isAndroid || Platform.isWindows;
  static bool get supportsBatteryOptimizationSettings => Platform.isAndroid;

  /// 初始化
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    if (Platform.isWindows) {
      _ensureWindowsChannel();
      final actualAutoStart = await _getWindowsAutoStartEnabled();
      await _prefs?.setBool(_autoStartKey, actualAutoStart);
      if (actualAutoStart && !getKeepAlive()) {
        await _prefs?.setBool(_keepAliveKey, true);
      }
    }

    _isKeepAliveEnabled = getKeepAlive();
    
    // 根据设置应用后台保活
    await applyKeepAlive();
  }

  static void _ensureWindowsChannel() {
    if (_windowsChannelReady) return;
    _windowsChannelReady = true;
    _windowsPlatform.setMethodCallHandler((call) async {
      if (call.method == 'onTrayReconnect') {
        _trayReconnectController.add(null);
      }
    });
  }

  /// 获取保留后台设置
  static bool getKeepAlive() {
    return _prefs?.getBool(_keepAliveKey) ?? true;
  }

  /// 设置保留后台
  static Future<bool> setKeepAlive(bool value) async {
    if (Platform.isWindows && !value && getAutoStart()) {
      await setAutoStart(false);
    }

    _isKeepAliveEnabled = value;
    final result = await _prefs?.setBool(_keepAliveKey, value) ?? false;
    await applyKeepAlive();
    return result;
  }

  /// 获取开机自启设置
  static bool getAutoStart() {
    return _prefs?.getBool(_autoStartKey) ?? false;
  }

  /// 设置开机自启
  static Future<bool> setAutoStart(bool value) async {
    if (Platform.isWindows) {
      if (value && !getKeepAlive()) {
        _isKeepAliveEnabled = true;
        await _prefs?.setBool(_keepAliveKey, true);
        await applyKeepAlive();
      }
      final actualValue = await _setWindowsAutoStartEnabled(value);
      return await _prefs?.setBool(_autoStartKey, actualValue) ?? false;
    }

    final result = await _prefs?.setBool(_autoStartKey, value) ?? false;

    // Android 上检查权限
    if (Platform.isAndroid && value) {
      final hasPermission = await _checkAutoStartPermission();
      if (!hasPermission) {
        // 尝试打开设置页面
        await _requestAutoStartPermission();
      }
    }
    
    return result;
  }

  /// 应用后台保活设置
  static Future<void> applyKeepAlive() async {
    if (Platform.isWindows) {
      if (_isKeepAliveEnabled) {
        await _initializeTray();
      } else {
        await _setCloseToTrayEnabled(false);
        await _disposeTray();
      }
      await _setCloseToTrayEnabled(_isKeepAliveEnabled);
      return;
    }

    if (_isKeepAliveEnabled) {
      // 启用屏幕常亮（防止应用被系统休眠）
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  }

  /// 检查是否支持开机自启（仅 Android）
  static Future<bool> isAutoStartSupported() async {
    if (Platform.isWindows) return true;
    if (!Platform.isAndroid) return false;
    
    try {
      final bool result =
          await _androidPlatform.invokeMethod('isAutoStartSupported');
      return result;
    } catch (e, stackTrace) {
      LogUtil.error('检查开机自启支持失败', e, stackTrace);
      return false;
    }
  }

  /// 检查开机自启权限（仅 Android）
  static Future<bool> _checkAutoStartPermission() async {
    if (!Platform.isAndroid) return false;
    
    try {
      final bool result =
          await _androidPlatform.invokeMethod('checkAutoStartPermission');
      return result;
    } catch (e, stackTrace) {
      LogUtil.error('检查开机自启权限失败', e, stackTrace);
      return false;
    }
  }

  /// 请求开机自启权限（打开设置页面）
  static Future<void> _requestAutoStartPermission() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _androidPlatform.invokeMethod('requestAutoStartPermission');
    } catch (e, stackTrace) {
      LogUtil.error('请求开机自启权限失败', e, stackTrace);
    }
  }

  /// 打开电池优化白名单设置
  static Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _androidPlatform.invokeMethod('openBatteryOptimizationSettings');
    } catch (e, stackTrace) {
      LogUtil.error('打开电池优化设置失败', e, stackTrace);
    }
  }

  static Future<void> _setCloseToTrayEnabled(bool value) async {
    if (!Platform.isWindows) return;

    try {
      await _windowsPlatform.invokeMethod(
        'setCloseToTrayEnabled',
        {'enabled': value},
      );
    } catch (e, stackTrace) {
      LogUtil.error('设置 Windows 托盘常驻状态失败', e, stackTrace);
    }
  }

  static Future<void> _initializeTray() async {
    if (!Platform.isWindows) return;

    try {
      await _windowsPlatform.invokeMethod('initializeTray');
    } catch (e, stackTrace) {
      LogUtil.error('初始化 Windows 托盘失败', e, stackTrace);
    }
  }

  static Future<void> _disposeTray() async {
    if (!Platform.isWindows) return;

    try {
      await _windowsPlatform.invokeMethod('disposeTray');
    } catch (e, stackTrace) {
      LogUtil.error('释放 Windows 托盘失败', e, stackTrace);
    }
  }

  static Future<void> showMainWindow() async {
    if (!Platform.isWindows) return;

    try {
      await _windowsPlatform.invokeMethod('showMainWindow');
    } catch (e, stackTrace) {
      LogUtil.error('显示 Windows 主窗口失败', e, stackTrace);
    }
  }

  static Future<void> hideMainWindow() async {
    if (!Platform.isWindows) return;

    try {
      await _windowsPlatform.invokeMethod('hideMainWindow');
    } catch (e, stackTrace) {
      LogUtil.error('隐藏 Windows 主窗口失败', e, stackTrace);
    }
  }

  static Future<bool> _getWindowsAutoStartEnabled() async {
    if (!Platform.isWindows) return false;

    try {
      final bool? result = await _windowsPlatform.invokeMethod<bool>(
        'getAutoStartEnabled',
      );
      return result ?? false;
    } catch (e, stackTrace) {
      LogUtil.error('读取 Windows 开机自启状态失败', e, stackTrace);
      return false;
    }
  }

  static Future<bool> _setWindowsAutoStartEnabled(bool value) async {
    if (!Platform.isWindows) return false;

    try {
      final bool? result = await _windowsPlatform.invokeMethod<bool>(
        'setAutoStartEnabled',
        {'enabled': value},
      );
      return result ?? false;
    } catch (e, stackTrace) {
      LogUtil.error('设置 Windows 开机自启失败', e, stackTrace);
      return false;
    }
  }
}
