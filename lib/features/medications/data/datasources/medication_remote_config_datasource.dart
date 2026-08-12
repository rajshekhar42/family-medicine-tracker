import 'dart:convert';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/med_type_config.dart';
import '../../../../core/constants/app_constants.dart';

abstract class MedicationRemoteConfigDataSource {
  Future<MedTypeConfig> getMedTypeConfig();
}

class MedicationRemoteConfigDataSourceImpl implements MedicationRemoteConfigDataSource {
  final FirebaseRemoteConfig? _remoteConfig;

  MedicationRemoteConfigDataSourceImpl([this._remoteConfig]);

  static const String _fallbackConfigJson = '''
  {
    "medTypeUnits": [
      {
        "id": "tablet",
        "displayName": "Tablet",
        "dosageEnabled": true,
        "dosageUnits": ["mg", "mcg", "g"],
        "quantityEnabled": true,
        "quantityUnits": ["tab"]
      },
      {
        "id": "capsule",
        "displayName": "Capsule",
        "dosageEnabled": true,
        "dosageUnits": ["mg", "mcg", "g"],
        "quantityEnabled": true,
        "quantityUnits": ["cap"]
      },
      {
        "id": "syrup",
        "displayName": "Syrup",
        "dosageEnabled": false,
        "dosageUnits": [],
        "quantityEnabled": true,
        "quantityUnits": ["ml", "spoon"]
      },
      {
        "id": "powder",
        "displayName": "Powder",
        "dosageEnabled": false,
        "dosageUnits": [],
        "quantityEnabled": true,
        "quantityUnits": ["sachet", "spoon"]
      },
      {
        "id": "cream",
        "displayName": "Cream",
        "dosageEnabled": false,
        "dosageUnits": [],
        "quantityEnabled": false,
        "quantityUnits": []
      },
      {
        "id": "injection",
        "displayName": "Injection",
        "dosageEnabled": true,
        "dosageUnits": ["mg", "mcg", "ml"],
        "quantityEnabled": true,
        "quantityUnits": ["vial", "ampoule", "ml"]
      },
      {
        "id": "other",
        "displayName": "Other",
        "dosageEnabled": true,
        "dosageUnits": ["mg", "mcg", "g"],
        "quantityEnabled": true,
        "quantityUnits": ["qu"]
      }
    ]
  }
  ''';

  @override
  Future<MedTypeConfig> getMedTypeConfig() async {
    if (_remoteConfig == null) {
      return _parseJson(_fallbackConfigJson);
    }

    try {
      // Set short timeouts to avoid blocking UI if network is poor
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      
      await _remoteConfig.fetchAndActivate();
      final jsonString = _remoteConfig.getString(AppConstants.remoteConfigMedTypeUnits);
      
      if (jsonString.isNotEmpty) {
        return _parseJson(jsonString);
      }
    } catch (e) {
      debugPrint('Firebase Remote Config failed: $e, falling back to local configurations.');
    }

    return _parseJson(_fallbackConfigJson);
  }

  MedTypeConfig _parseJson(String jsonString) {
    final Map<String, dynamic> parsed = jsonDecode(jsonString);
    final List<dynamic> list = parsed['medTypeUnits'] as List<dynamic>;

    final types = list.map((item) {
      final map = item as Map<String, dynamic>;
      return MedTypeUnit(
        id: map['id'] as String,
        displayName: map['displayName'] as String,
        dosageEnabled: map['dosageEnabled'] as bool,
        dosageUnits: List<String>.from(map['dosageUnits'] as List<dynamic>),
        quantityEnabled: map['quantityEnabled'] as bool,
        quantityUnits: List<String>.from(map['quantityUnits'] as List<dynamic>),
      );
    }).toList();

    return MedTypeConfig(types: types);
  }
}
