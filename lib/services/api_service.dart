// lib/services/api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saferoute/models/tourist_model.dart';
import 'package:saferoute/models/location_ping_model.dart';
import 'package:saferoute/models/zone_model.dart';
import 'package:saferoute/models/trail_graph_model.dart';
import 'package:saferoute/models/emergency_contact_model.dart';
import 'package:saferoute/services/secure_storage_service.dart';
import 'package:uuid/uuid.dart';
import 'package:saferoute/utils/constants.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  late Dio _dio;
  final SecureStorageService _secureStorage = SecureStorageService();
  static final ApiService _instance = ApiService._internal();

  factory ApiService() => _instance;

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: kBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // ✅ JWT-BASED AUTH: Use Bearer token instead of plaintext tourist_id
        final token = await _secureStorage.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        if (kDebugMode) {
          debugPrint('REQUEST[${options.method}] => PATH: ${options.path}');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          debugPrint('RESPONSE[${response.statusCode}] => PATH: ${response.requestOptions.path}');
        }
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        // Handle 401 Unauthorized (token expired)
        if (e.response?.statusCode == 401) {
          debugPrint('❌ Token expired or invalid');
          // Auth refresh could be added here
        }
        if (kDebugMode) {
          debugPrint('DIO_ERROR[${e.type}] => PATH: ${e.requestOptions.path} MESSAGE: ${e.message}');
          if (e.response != null) {
            debugPrint('DIO_ERROR_RESPONSE => DATA: ${e.response?.data}');
          }
        }
        return handler.next(e);
      },
    ));
  }

  ApiException _handleDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.sendTimeout) {
      return ApiException("Server unreachable or slow connection");
    } else if (e.type == DioExceptionType.receiveTimeout) {
      return ApiException("Server took too long to respond");
    } else if (e.response != null) {
      final status = e.response!.statusCode;
      final data = e.response!.data;
      
      if (status == 422) {
        return ApiException("Data validation error. Please check your inputs.");
      } else if (status == 400 || status == 401) {
        return ApiException(data['detail'] ?? data['message'] ?? (status == 401 ? "Unauthorized" : "Bad request"));
      } else if (status == 500) {
        return ApiException("Internal Server Error. Check backend logs.");
      }
    }
    return ApiException("Network error: ${e.message}");
  }

  /// Register tourist and get JWT token
  /// Returns: {"token": "...", "tourist": {...}}
  Future<Map<String, dynamic>> registerTouristWithToken(Map<String, dynamic> formData) async {
    try {
      // Try online first
      final response = await _dio.post('/tourist/register', data: formData).timeout(const Duration(seconds: 10));
      
      // Extract token and save it
      final token = response.data['token'];
      final touristData = response.data['tourist'];
      
      if (token != null) {
        final touristId = touristData['tourist_id'];
        await _secureStorage.saveToken(token);
        await _secureStorage.saveTouristId(touristId);
        debugPrint('✅ JWT token saved for tourist: $touristId');
      }
      
      return {
        'token': token,
        'tourist': Tourist.fromJson(touristData),
      };
    } catch (e) {
      debugPrint("API Error during registration: $e. Using offline fallback.");
      
      try {
        final String touristId = "TID-OFFLINE-${const Uuid().v4().toUpperCase().substring(0, 8)}";
        
        // Ensure all required fields for the Tourist model are present
        final offlineTourist = Tourist(
          touristId: touristId,
          fullName: formData["full_name"] ?? "Tourist",
          documentType: formData["document_type"] == "PASSPORT" ? DocumentType.PASSPORT : DocumentType.AADHAAR,
          documentNumber: formData["document_number"] ?? "0000-0000-0000",
          photoBase64: formData["photo_base64"] ?? "",
          emergencyContactName: formData["emergency_contact_name"] ?? "Emergency",
          emergencyContactPhone: formData["emergency_contact_phone"] ?? "112",
          tripStartDate: DateTime.tryParse(formData["trip_start_date"] ?? "") ?? DateTime.now(),
          tripEndDate: DateTime.tryParse(formData["trip_end_date"] ?? "") ?? DateTime.now().add(const Duration(days: 7)),
          destinationState: formData["destination_state"] ?? "Uttarakhand",
          qrData: "SAFEROUTE-$touristId",
          createdAt: DateTime.now(),
          blockchainHash: "0x_offline_secured_${touristId.toLowerCase()}",
          selectedDestinations: (formData["selected_destinations"] as List?)?.map((d) => DestinationVisit(
            destinationId: d['destination_id'] ?? 'UK_001',
            name: d['name'] ?? 'Destination',
            visitDateFrom: DateTime.tryParse(d['visit_date_from'] ?? "") ?? DateTime.now(),
            visitDateTo: DateTime.tryParse(d['visit_date_to'] ?? "") ?? DateTime.now().add(const Duration(days: 2)),
          )).toList() ?? [],
          connectivityLevel: "MODERATE",
          bloodGroup: formData["blood_group"] ?? "Unknown",
          offlineModeRequired: true,
          riskLevel: "LOW",
        );
        
        // Save offline token (empty JWT for offline mode)
        await _secureStorage.saveTouristId(touristId);
        
        return {
          'token': 'offline-token',
          'tourist': offlineTourist,
        };
      } catch (innerError) {
        debugPrint("CRITICAL: Even offline fallback failed: $innerError");
        // Last-ditch absolute fallback
        final emergencyTourist = Tourist(
          touristId: "TID-EMERGENCY-${DateTime.now().millisecondsSinceEpoch}",
          fullName: "Guest Tourist",
          documentType: DocumentType.AADHAAR,
          documentNumber: "UNKNOWN",
          photoBase64: "",
          emergencyContactName: "Emergency",
          emergencyContactPhone: "112",
          tripStartDate: DateTime.now(),
          tripEndDate: DateTime.now().add(const Duration(days: 7)),
          destinationState: "Uttarakhand",
          qrData: "EMERGENCY",
          createdAt: DateTime.now(),
          blockchainHash: "0x_emergency",
          bloodGroup: "Unknown",
        );
        
        return {
          'token': 'offline-token',
          'tourist': emergencyTourist,
        };
      }
    }
  }

  /// Recover tourist data using ID
  Future<Map<String, dynamic>> loginTourist(String touristId) async {
    try {
      final response = await _dio.post('/tourist/login', data: {'tourist_id': touristId});
      return {
        'tourist': Tourist.fromJson(response.data['tourist']),
        'token':   response.data['token'],
      };
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ApiException("Login failed: $e");
    }
  }

  Future<bool> sendLocationPing(LocationPing ping) async {
    try {
      final response = await _dio.post('/location/ping', data: ping.toJson());
      return response.statusCode == 200 || response.statusCode == 201;
    } on DioException catch (e) {
      debugPrint("Ping failed: ${e.message}");
      return false;
    } catch (e) {
      debugPrint("Ping failed: $e");
      return false;
    }
  }

  // FIX: Added touristId parameter — backend now persists SOS events linked to tourist.
  Future<bool> sendSosAlert(
    double lat,
    double lng,
    String triggerType, {
    String? touristId,
  }) async {
    try {
      final response = await _dio
          .post('/sos/trigger', data: {
            'tourist_id': touristId ?? 'UNKNOWN',
            'latitude': lat,
            'longitude': lng,
            'trigger_type': triggerType,
            'timestamp': DateTime.now().toIso8601String(),
          })
          .timeout(const Duration(seconds: 10)); // Fast fail on SOS path
      return response.statusCode == 200 || response.statusCode == 201;
    } on DioException catch (e) {
      debugPrint("SOS failed: ${e.message}");
      return false;
    } catch (e) {
      debugPrint("SOS failed: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>> registerAuthority(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/auth/register/authority', data: data);
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ApiException("Authority registration failed: $e");
    }
  }

  Future<Map<String, dynamic>> loginAuthority(String email, String password) async {
    try {
      final response = await _dio.post('/auth/login/authority', data: {
        'email': email,
        'password': password,
      });
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ApiException("Login failed: $e");
    }
  }

  Future<List<dynamic>> getActiveTouristZones() async {
    try {
      final response = await _dio.get('/zones/active');
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      return [];
    }
  }

  /// Typed zone fetch for a specific destination
  Future<List<ZoneModel>> getZonesForDestination(String destinationId) async {
    try {
      final response = await _dio.get('/zones', queryParameters: {'destination_id': destinationId});
      return (response.data as List)
          .map((j) => ZoneModel.fromJson(j as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      return [];
    }
  }

  /// Fetch trail graph for a destination (offline pathfinding)
  Future<TrailGraph?> getTrailGraph(String destinationId) async {
    try {
      final response = await _dio.get('/destinations/$destinationId/trail-graph');
      return TrailGraph.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _handleDioError(e);
    } catch (e) {
      return null;
    }
  }

  /// Fetch emergency contacts for a destination
  Future<List<EmergencyContact>> getEmergencyContacts(String destinationId) async {
    try {
      final response = await _dio.get('/destinations/$destinationId/detail');
      final contacts = response.data['emergency_contacts'] as List? ?? [];
      return contacts
          .map((c) => EmergencyContact.fromJson(c as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getStates() async {
    try {
      final response = await _dio.get('/destinations/states');
      return response.data;
    } catch (e) {
      debugPrint("API Error fetching states: $e");
      return <String>[];   // no hardcoded fallbacks — use DB cache instead
    }
  }

  Future<List<dynamic>> getDestinationsByState(String state) async {
    try {
      final response = await _dio.get('/destinations/$state');
      return response.data;
    } catch (e) {
      debugPrint("API Error fetching destinations: $e");
      return <dynamic>[];  // caller handles offline via DB cache
    }
  }

  Future<bool> checkServerHealth() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> post(String path, dynamic data) async {
    try {
      final response = await _dio.post(path, data: data);
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ApiException("Request failed: $e");
    }
  }

  /// Authority — list SOS events in jurisdiction
  Future<List<dynamic>> getSosEvents() async {
    try {
      final response = await _dio.get('/sos/events');
      return response.data as List;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Authority — respond to and close an SOS event
  Future<void> respondToSos(int sosId) async {
    try {
      await _dio.post('/sos/events/$sosId/respond');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }
}

