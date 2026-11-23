import 'dart:async';
import 'dart:typed_data';

import 'package:oronbox/src/core/logging/logging_service.dart';
import 'package:oronbox/src/device/core/event_bus.dart';
import 'package:oronbox/src/device/xiaomi/systems/xiaomi_system.dart';
import 'package:oronbox/src/device/xiaomi/protocol/generated/wear.pb.dart'
    as pb;
import 'package:oronbox/src/device/xiaomi/protocol/generated/wear_thirdparty_app.pb.dart'
    as pb_thirdparty;

class ThirdpartyAppInfo {
  ThirdpartyAppInfo({required this.packageName, required this.fingerprint});

  final String packageName;
  final Uint8List fingerprint;
}

class XiaomiThirdpartyAppSystem extends XiaomiPbSystem {
  static final _log = getLogger('XiaomiThirdpartyAppSystem');

  final _connectedApps = <String, ThirdpartyAppInfo>{};

  Future<void> sendPhoneMessage(
    String packageName,
    Uint8List payload, {
    ThirdpartyAppInfo? app,
  }) async {
    final resolvedApp =
        app ??
        _connectedApps[packageName] ??
        ThirdpartyAppInfo(packageName: packageName, fingerprint: Uint8List(0));
    // #region agent log
    _agentLog('B', 'thirdparty_app_system.dart:sendPhoneMessage', 'queued', {
      'package': packageName,
      'bytes': payload.length,
      'fingerprint': resolvedApp.fingerprint.length,
      'cached': _connectedApps.containsKey(packageName),
      'sessions': _connectedApps.keys.toList(),
    });
    // #endregion
    _log.info(
      '[${entity.id}] sending interconnect message to $packageName '
      '(${payload.length} bytes, fingerprint=${resolvedApp.fingerprint.length} '
      'bytes, source=${app != null ? 'installed-app' : 'session'})',
    );
    await component.sendPbPacket(
      _buildThirdpartyAppMsgContent(resolvedApp, payload),
    );
    _log.info('[${entity.id}] interconnect message queued for $packageName');
  }

  Future<void> launchApp(ThirdpartyAppInfo app, String page) async {
    await component.sendPbPacket(_buildThirdpartyAppLaunch(app, page));
  }

  Future<void> uninstallApp(ThirdpartyAppInfo app) async {
    await component.sendPbPacket(_buildThirdpartyAppUninstall(app));
  }

  Future<void> syncStatus(
    ThirdpartyAppInfo app,
    pb_thirdparty.PhoneAppStatus_Status status,
  ) async {
    await component.sendPbPacket(
      _buildThirdpartyAppSyncStatus(_toBasicInfo(app), status),
    );
  }

  void _handleBasicInfo(pb_thirdparty.BasicInfo basicInfo) {
    final packageName = basicInfo.packageName.trim();
    if (packageName.isEmpty) {
      _log.warning(
        '[${entity.id}] ignoring interconnect session without package name',
      );
      return;
    }
    final info = ThirdpartyAppInfo(
      packageName: packageName,
      fingerprint: Uint8List.fromList(basicInfo.fingerprint),
    );
    _connectedApps[packageName] = info;
    // #region agent log
    _agentLog('C', 'thirdparty_app_system.dart:_handleBasicInfo', 'session', {
      'package': packageName,
      'fingerprint': basicInfo.fingerprint.length,
    });
    // #endregion
    _log.info(
      '[${entity.id}] interconnect session opened by $packageName '
      '(fingerprint=${basicInfo.fingerprint.length} bytes)',
    );
    unawaited(
      component
          .sendPbPacket(
            _buildThirdpartyAppSyncStatus(
              basicInfo,
              pb_thirdparty.PhoneAppStatus_Status.CONNECTED,
            ),
          )
          .then(
            (_) => _log.info(
              '[${entity.id}] confirmed interconnect session for $packageName',
            ),
            onError: (Object error, StackTrace stackTrace) => _log.warning(
              '[${entity.id}] failed to confirm interconnect session for '
              '$packageName',
              error,
              stackTrace,
            ),
          ),
    );
  }

  void _handleMessageContent(pb_thirdparty.MessageContent message) {
    final declaredPackage = message.hasBasicInfo()
        ? message.basicInfo.packageName.trim()
        : '';
    final pkgName = declaredPackage.isNotEmpty
        ? declaredPackage
        : (_connectedApps.length == 1 ? _connectedApps.keys.single : '');
    if (declaredPackage.isEmpty && pkgName.isNotEmpty) {
      _log.warning(
        '[${entity.id}] interconnect reply omitted package name; '
        'using sole active session $pkgName',
      );
    }
    // #region agent log
    _agentLog('D', 'thirdparty_app_system.dart:_handleMessageContent', 'rx', {
      'package': pkgName,
      'declared': declaredPackage,
      'bytes': message.content.length,
      'hasBasicInfo': message.hasBasicInfo(),
      'sessions': _connectedApps.keys.toList(),
    });
    // #endregion
    if (pkgName.isEmpty) {
      _log.warning(
        '[${entity.id}] interconnect reply cannot be routed: '
        'package missing, activeSessions=${_connectedApps.keys}',
      );
    }
    _log.info(
      '[${entity.id}] received interconnect message from $pkgName '
      '(${message.content.length} bytes, basicInfo=${message.hasBasicInfo()})',
    );
    entity.emit(
      InterconnectMessage(
        deviceId: entity.id,
        pkgName: pkgName,
        payload: Uint8List.fromList(message.content),
      ),
    );
  }

  @override
  void onWearPacket(pb.WearPacket packet) {
    if (packet.whichPayload() != pb.WearPacket_Payload.thirdpartyApp) return;
    final app = packet.thirdpartyApp;

    switch (app.whichPayload()) {
      case pb_thirdparty.ThirdpartyApp_Payload.basicInfo:
        _handleBasicInfo(app.basicInfo);
      case pb_thirdparty.ThirdpartyApp_Payload.messageContent:
        _handleMessageContent(app.messageContent);
      default:
        break;
    }
  }
}

pb.WearPacket _buildThirdpartyAppSyncStatus(
  pb_thirdparty.BasicInfo basicInfo,
  pb_thirdparty.PhoneAppStatus_Status status,
) {
  final phoneStatus = pb_thirdparty.PhoneAppStatus(
    basicInfo: basicInfo,
    status: status,
  );

  return pb.WearPacket(
    type: pb.WearPacket_Type.THIRDPARTY_APP,
    id: pb_thirdparty.ThirdpartyApp_ThirdpartyAppID.SYNC_PHONE_APP_STATUS.value,
    thirdpartyApp: pb_thirdparty.ThirdpartyApp(appStatus: phoneStatus),
  );
}

pb.WearPacket _buildThirdpartyAppMsgContent(
  ThirdpartyAppInfo app,
  Uint8List data,
) {
  return pb.WearPacket(
    type: pb.WearPacket_Type.THIRDPARTY_APP,
    id: pb_thirdparty.ThirdpartyApp_ThirdpartyAppID.SEND_PHONE_MESSAGE.value,
    thirdpartyApp: pb_thirdparty.ThirdpartyApp(
      messageContent: pb_thirdparty.MessageContent(
        basicInfo: _toBasicInfo(app),
        content: data,
      ),
    ),
  );
}

pb.WearPacket _buildThirdpartyAppLaunch(ThirdpartyAppInfo app, String page) {
  return pb.WearPacket(
    type: pb.WearPacket_Type.THIRDPARTY_APP,
    id: pb_thirdparty.ThirdpartyApp_ThirdpartyAppID.LAUNCH_APP.value,
    thirdpartyApp: pb_thirdparty.ThirdpartyApp(
      launchInfo: pb_thirdparty.LaunchInfo(
        basicInfo: _toBasicInfo(app),
        uri: page,
      ),
    ),
  );
}

pb.WearPacket _buildThirdpartyAppUninstall(ThirdpartyAppInfo app) {
  return pb.WearPacket(
    type: pb.WearPacket_Type.THIRDPARTY_APP,
    id: pb_thirdparty.ThirdpartyApp_ThirdpartyAppID.REMOVE_APP.value,
    thirdpartyApp: pb_thirdparty.ThirdpartyApp(basicInfo: _toBasicInfo(app)),
  );
}

void _agentLog(
  String hypothesisId,
  String location,
  String message,
  Map<String, Object?> data,
) {
  logDiagnostic(
    getLogger('Interconnect'),
    Level.INFO,
    '[ic] $location: $message',
    fields: {...data, 'hypothesisId': hypothesisId},
  );
}

pb_thirdparty.BasicInfo _toBasicInfo(ThirdpartyAppInfo app) {
  return pb_thirdparty.BasicInfo(
    packageName: app.packageName,
    fingerprint: app.fingerprint,
  );
}
