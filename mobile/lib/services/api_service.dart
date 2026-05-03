// lib/services/api_service.dart
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:saferoute/models/tourist_model.dart';
import 'package:saferoute/models/location_ping_model.dart';
import 'package:saferoute/models/zone_model.dart';
import 'package:saferoute/models/trail_graph_model.dart';
import 'package:saferoute/models/emergency_contact_model.dart';
import 'package:saferoute/services/secure_storage_service.dart';
import 'package:uuid/uuid.dart';
import 'package:saferoute/utils/constants.dart';
import 'package:saferoute/utils/validators.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Custom Exceptions
// ---------------------------------------------------------------------------

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Thrown specifically when the user hits a 429 rate limit.
/// UI layer should catch this and show user-friendly feedback.
class RateLimitException extends ApiException {
  final Duration? retryAfter;
  RateLimitException({this.retryAfter})
      : super(
          "Too many requests. Please wait a moment.",
          statusCode: 429,
        );
}

/// Thrown when token storage is corrupted or tokens are invalid.
/// UI layer should catch this and trigger a force-logout + recovery flow.
class AuthCorruptionException extends ApiException {
  AuthCorruptionException()
      : super(
          "Session expired or corrupted. Please log in again.",
          statusCode: 401,
        );
}

class SosAlertResult {
  final bool accepted;
  final bool dispatched;
  final String status;
  final String dispatchStatus;

  const SosAlertResult({
    required this.accepted,
    required this.dispatched,
    required this.status,
    required this.dispatchStatus,
  });
}

// ---------------------------------------------------------------------------
// ApiService — Production-Grade Network Layer
// ---------------------------------------------------------------------------

class ApiService {
  late Dio _dio;

  /// Dedicated SOS Dio instance — bypasses normal retry queue entirely
  late Dio _sosDio;

  final SecureStorageService _secureStorage = SecureStorageService();

  // Dedup concurrent refresh attempts (FIX #1)
  Future<String?>? _refreshFuture;

  static final ApiService _instance = ApiService._internal();
  static final Random _jitterRng = Random();

  factory ApiService() => _instance;

  ApiService._internal() {
    debugPrint('🚀 ApiService initialized with baseUrl: $kBaseUrl');
    _validateNetworkConfiguration();

    // --- Primary API client ---
    _dio = _createDio(
      BaseOptions(
        baseUrl: kBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    _dio.interceptors.add(_buildInterceptor());

    // --- SOS Priority Channel — separate Dio, separate connection pool ---
    _sosDio = _createDio(
      BaseOptions(
        baseUrl: kBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 10),
      ),
    );
    _sosDio.interceptors.add(_buildInterceptor());
  }

  void _validateNetworkConfiguration() {
    final uri = Uri.tryParse(kBaseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('Invalid SAFEROUTE_API_BASE_URL: $kBaseUrl');
    }

    if (kReleaseMode && uri.scheme != 'https') {
      throw StateError(
        'SECURITY ERROR: release builds must use HTTPS. '
        'Pass --dart-define=SAFEROUTE_API_BASE_URL=https://...',
      );
    }

    if (kPinnedCertificateSha256.isNotEmpty && uri.scheme != 'https') {
      throw StateError('TLS certificate pinning requires an HTTPS API URL.');
    }
  }

  Dio _createDio(BaseOptions options) {
    final dio = Dio(options);
    _configureCertificatePinning(dio);
    return dio;
  }

  void _configureCertificatePinning(Dio dio) {
    final expectedPin =
        kPinnedCertificateSha256.replaceAll(':', '').trim().toLowerCase();
    if (expectedPin.isEmpty) return;

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () =>
          HttpClient()..idleTimeout = const Duration(seconds: 5),
      validateCertificate: (
        X509Certificate? certificate,
        String host,
        int port,
      ) {
        if (certificate == null) return false;
        final actualPin =
            sha256.convert(certificate.der).toString().toLowerCase();
        final matches = actualPin == expectedPin;
        if (!matches) {
          debugPrint('TLS pin mismatch for $host:$port');
        }
        return matches;
      },
    );
  }

  // -------------------------------------------------------------------------
  // INTERCEPTOR: Auth, Correlation ID, Token Refresh, Rate Limit UX
  // -------------------------------------------------------------------------

  InterceptorsWrapper _buildInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        // 1. JWT-BASED AUTH
        final token = await _secureStorage.getToken();
        if (token != null && token.isNotEmpty) {
          // FIX #7: Validate token structure before sending
          if (!_isValidJwtStructure(token)) {
            debugPrint('🛑 Corrupted token detected. Forcing logout.');
            await _secureStorage.clearAuthData();
            // Don't attach a garbage token — let the request go unauthenticated
          } else {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }

        // 2. CORRELATION ID — reuse existing if set (FIX #5: propagation)
        if (options.headers['X-Correlation-ID'] == null) {
          options.headers['X-Correlation-ID'] = const Uuid().v4();
        }

        final cid = options.headers['X-Correlation-ID'];

        // 3. USER TYPE & GUEST CONTEXT (Elite Readiness)
        final prefs = await SharedPreferences.getInstance();
        final userState = prefs.getString('user_state') ?? 'GUEST';
        options.headers['X-User-Type'] = userState;

        if (userState == 'GUEST') {
          final guestId = prefs.getString('guest_session_id');
          if (guestId != null) {
            options.headers['X-Guest-Session-ID'] = guestId;
          }
        }

        debugPrint('REQUEST[${options.method}] => ${options.path} [CID: $cid]');
        return handler.next(options);
      },
      onResponse: (response, handler) {
        final cid = response.requestOptions.headers['X-Correlation-ID'] ?? '-';
        if (kDebugMode) {
          debugPrint(
              'RESPONSE[${response.statusCode}] => ${response.requestOptions.path} [CID: $cid]');
        }
        return handler.next(response);
      },
      onError: (DioException e, handler) async {
        final cid = e.requestOptions.headers['X-Correlation-ID'] ?? '-';
        final statusCode = e.response?.statusCode;

        // --- FIX #8: Rate Limit UX — surface 429 as a typed exception ---
        if (statusCode == 429) {
          final retryAfterSec = int.tryParse(
            e.response?.headers.value('retry-after') ?? '',
          );
          debugPrint(
              '⏳ Rate limited [CID: $cid]. Retry-After: ${retryAfterSec}s');
          return handler.reject(
            DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: DioExceptionType.badResponse,
              error: RateLimitException(
                retryAfter: retryAfterSec != null
                    ? Duration(seconds: retryAfterSec)
                    : null,
                ),
            ),
          );
        }

        // --- Handle 401 Unauthorized: Token Refresh ---
        if (statusCode == 401) {
          final cid = e.requestOptions.headers['X-Correlation-ID'] ?? '-';

          // DEDUPLICATION: If a refresh is already in progress, wait for it
          if (_refreshFuture != null) {
            debugPrint('⏳ Refresh already in progress [CID: $cid]. Waiting...');
            final newToken = await _refreshFuture;
            if (newToken != null) {
              final retryOptions = e.requestOptions;
              retryOptions.headers['Authorization'] = 'Bearer $newToken';
              final isSos = retryOptions.path.contains('sos');
              final retryDio = isSos ? _sosDio : _dio;
              return handler.resolve(await retryDio.fetch(retryOptions));
            }
          }

          final refreshToken = await _secureStorage.getRefreshToken();
          if (refreshToken != null && _isValidJwtStructure(refreshToken)) {
            try {
              debugPrint('🔄 Token expired [CID: $cid]. Attempting refresh...');

              // Define the refresh operation
              _refreshFuture = () async {
                try {
                  final refreshDio = _createDio(
                    BaseOptions(
                      baseUrl: kBaseUrl,
                      connectTimeout: const Duration(seconds: 10),
                      receiveTimeout: const Duration(seconds: 10),
                      sendTimeout: const Duration(seconds: 10),
                    ),
                  );
                  final response = await refreshDio.post(
                    '/auth/refresh',
                    options: Options(headers: {
                      'Authorization': 'Bearer $refreshToken',
                      'X-Correlation-ID': cid,
                    }),
                  );
                  final access = response.data['token'] as String?;
                  final refresh = response.data['refresh_token'] as String?;

                  if (access != null) {
                    await _secureStorage.saveToken(access);
                    if (refresh != null) {
                      await _secureStorage.saveRefreshToken(refresh);
                    }
                    return access;
                  }
                  return null;
                } catch (err) {
                  debugPrint('❌ Internal Refresh Error: $err');
                  // If refresh explicitly returned 401, rethrow to clear session
                  if (err is DioException && err.response?.statusCode == 401) {
                    rethrow;
                  }
                  return null;
                }
              }();

              final newToken = await _refreshFuture;
              _refreshFuture = null; // Reset after completion

              if (newToken != null) {
                debugPrint('✅ Token refreshed successfully [CID: $cid]');
                final retryOptions = e.requestOptions;
                retryOptions.headers['Authorization'] = 'Bearer $newToken';
                final isSos = retryOptions.path.contains('sos');
                final retryDio = isSos ? _sosDio : _dio;
                return handler.resolve(await retryDio.fetch(retryOptions));
              }
            } catch (refreshError) {
              _refreshFuture = null;
              debugPrint('❌ Refresh failed [CID: $cid]: $refreshError');
              if (refreshError is DioException && refreshError.response?.statusCode == 401) {
                debugPrint('🛑 Refresh Token invalid [CID: $cid]. Clearing session.');
                await _secureStorage.clearAuthData();
                return handler.reject(
                  DioException(
                    requestOptions: e.requestOptions,
                    error: AuthCorruptionException(),
                  ),
                );
              }
            }
          }
          debugPrint('⚠️ Unauthorized [CID: $cid] but session preserved for manual retry.');
          return handler.reject(e);
        }

        if (kDebugMode) {
          debugPrint(
              'DIO_ERROR[${e.type}] => ${e.requestOptions.path} [CID: $cid] MSG: ${e.message}');
        }
        return handler.next(e);
      },
    );
  }

  // -------------------------------------------------------------------------
  // TOKEN VALIDATION (FIX #7)
  // -------------------------------------------------------------------------

  /// Quick structural check: a valid JWT has exactly 3 base64url segments.
  bool _isValidJwtStructure(String token) {
    if (token == 'offline-token') return true; // allow offline sentinel
    final parts = token.split('.');
    if (parts.length != 3) return false;
    // Each segment must be non-empty
    return parts.every((p) => p.isNotEmpty);
  }

  // -------------------------------------------------------------------------
  // ERROR HANDLER
  // -------------------------------------------------------------------------

  ApiException _handleDioError(DioException e) {
    // Propagate typed exceptions directly
    if (e.error is RateLimitException) return e.error as RateLimitException;
    if (e.error is AuthCorruptionException) {
      return e.error as AuthCorruptionException;
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiException("Server unreachable or slow connection");
    } else if (e.type == DioExceptionType.receiveTimeout) {
      return ApiException("Server took too long to respond");
    } else if (e.response != null) {
      final status = e.response!.statusCode;
      final data = e.response!.data;
      final detail = data is Map
          ? (data['detail'] ?? data['message'])?.toString()
          : data?.toString();

      if (status == 429) {
        return RateLimitException();
      } else if (status == 422) {
        return ApiException("Data validation error. Please check your inputs.",
            statusCode: 422);
      } else if (status == 400 || status == 401) {
        return ApiException(
          detail ?? (status == 401 ? "Unauthorized" : "Bad request"),
          statusCode: status,
        );
      } else if (status == 500) {
        return ApiException("Internal Server Error. Check backend logs.",
            statusCode: 500);
      }
    }
    return ApiException("Network error: ${e.message}");
  }

  // -------------------------------------------------------------------------
  // REGISTRATION
  // --------------------------------------------------
  Future<Map<String, dynamic>> registerTouristWithToken(
      Map<String, dynamic> formData) async {
    try {
      final response = await _retryWithBackoff(
        () => _dio
            .post('/v3/tourist/register', data: formData)
            .timeout(const Duration(seconds: 10)),
      );

      final token = response.data['token'];
      final refreshToken = response.data['refresh_token'];
      final touristData = response.data['tourist'];

      if (token != null) {
        final touristId = touristData['tourist_id'];
        await _secureStorage.saveToken(token);
        if (refreshToken != null) {
          await _secureStorage.saveRefreshToken(refreshToken);
        }
        await _secureStorage.saveTouristId(touristId);
        debugPrint('✅ JWT tokens saved for tourist: $touristId');
      }

      return {
        'token': token,
        'refresh_token': refreshToken,
        'tourist': Tourist.fromJson(touristData),
      };
    } catch (e) {
      if (e is ApiException && e.statusCode == 422) {
        debugPrint("Validation error during registration. Rethrowing.");
        rethrow;
      }
      debugPrint("API Error during registration: $e. Using offline fallback.");

      try {
        final String touristId =
            "TID-OFFLINE-${const Uuid().v4().toUpperCase().substring(0, 8)}";

        final offlineTourist = Tourist(
          touristId: touristId,
          fullName: formData["full_name"] ?? "Tourist",
          documentType: formData["document_type"] == "PASSPORT"
              ? DocumentType.PASSPORT
              : DocumentType.AADHAAR,
          documentNumber: formData["document_number"] ?? "0000-0000-0000",
          photoBase64: formData["photo_base64"] ?? "",
          emergencyContactName:
              formData["emergency_contact_name"] ?? "Emergency",
          emergencyContactPhone: formData["emergency_contact_phone"] ?? "112",
          tripStartDate: DateTime.tryParse(formData["trip_start_date"] ?? "") ??
              DateTime.now(),
          tripEndDate: DateTime.tryParse(formData["trip_end_date"] ?? "") ??
              DateTime.now().add(const Duration(days: 7)),
          destinationState: formData["destination_state"] ?? "Uttarakhand",
          qrData: "SAFEROUTE-$touristId",
          createdAt: DateTime.now(),
          selectedDestinations: (formData["selected_destinations"] as List?)
                  ?.map((d) => DestinationVisit(
                        destinationId: d['destination_id'] ?? 'UK_001',
                        name: d['name'] ?? 'Destination',
                        visitDateFrom:
                            DateTime.tryParse(d['visit_date_from'] ?? "") ??
                                 DateTime.now(),
                        visitDateTo:
                            DateTime.tryParse(d['visit_date_to'] ?? "") ??
                                 DateTime.now().add(const Duration(days: 2)),
                      ))
                  .toList() ??
              [],
          connectivityLevel: "MODERATE",
          bloodGroup: formData["blood_group"] ?? "Unknown",
          offlineModeRequired: true,
          riskLevel: "LOW",
        );

        await _secureStorage.saveTouristId(touristId);
        await _secureStorage.saveToken('offline-token');

        return {
          'token': 'offline-token',
          'tourist': offlineTourist,
        };
      } catch (innerError) {
        debugPrint("CRITICAL: Even offline fallback failed: $innerError");
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
          bloodGroup: "Unknown",
        );

        await _secureStorage.saveTouristId(emergencyTourist.touristId);
        await _secureStorage.saveToken('offline-token');

        return {
          'token': 'offline-token',
          'tourist': emergencyTourist,
        };
      }
    }
  }

  // -------------------------------------------------------------------------
  // REGISTRATION (MULTIPART V3)
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> registerTouristMultipart({
    required Map<String, String> fields,
    required String photoPath,
    required String docPath,
    Function(double)? onProgress,
  }) async {
    try {
      final Map<String, dynamic> formDataMap = Map<String, dynamic>.from(fields);

      formDataMap['profile_photo'] = await MultipartFile.fromFile(
        photoPath,
        filename: 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      formDataMap['document_scan'] = await MultipartFile.fromFile(
        docPath,
        filename: 'doc_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      final formData = FormData.fromMap(formDataMap);

      final response = await _dio.post(
        '/v3/tourist/register-multipart',
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0 && onProgress != null) {
            onProgress(sent / total);
          }
        },
      ).timeout(const Duration(seconds: 90));

      final token = response.data['token'];
      final refreshToken = response.data['refresh_token'];
      final touristData = response.data['tourist'];

      if (token != null) {
        final touristId = touristData['tourist_id'];
        await _secureStorage.saveToken(token);
        if (refreshToken != null) {
          await _secureStorage.saveRefreshToken(refreshToken);
        }
        await _secureStorage.saveTouristId(touristId);
      }

      return {
        'token': token,
        'refresh_token': refreshToken,
        'tourist': Tourist.fromJson(touristData),
      };
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ApiException("Identity protocol upload failed: $e");
    }
  }

  // -------------------------------------------------------------------------
  // SECURE MEDIA ACCESS (V3.1)
  // -------------------------------------------------------------------------

  Future<Uint8List> fetchSecureMedia(String objectKey) async {
    try {
      final response = await _dio.get(
        '/v3/media/download/$objectKey',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data);
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ApiException("Failed to fetch secure identity media: $e");
    }
  }

  // -------------------------------------------------------------------------
  // LOGIN
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> loginTourist(String touristId) async {
    try {
      final response =
          await _retryWithBackoff(() => _dio.post('/v3/tourist/login', data: {
                'tourist_id': touristId,
              }));
      final token = response.data['token'];
      final refreshToken = response.data['refresh_token'];
      final touristData = response.data['tourist'];

      if (token != null && token is String && token.isNotEmpty) {
        await _secureStorage.saveToken(token);
        if (refreshToken != null) {
          await _secureStorage.saveRefreshToken(refreshToken);
        }
        await _secureStorage.saveTouristId(touristId);
      }

      return {
        'token': token,
        'refresh_token': refreshToken,
        'tourist': Tourist.fromJson(touristData),
      };
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ApiException("Login failed: $e");
    }
  }

  // -------------------------------------------------------------------------
  // LOCATION PING
  // -------------------------------------------------------------------------

  Future<bool> sendLocationPing(LocationPing ping) async {
    final coordError = Validators.validateCoordinates(ping.latitude, ping.longitude);
    if (coordError != null) {
      debugPrint("❌ Invalid coordinates: $coordError");
      return false;
    }

    final speedError = Validators.validateSpeed(ping.speedKmh);
    if (speedError != null) {
      debugPrint("❌ Invalid speed: $speedError");
      return false;
    }

    final accuracyError = Validators.validateAccuracy(ping.accuracyMeters);
    if (accuracyError != null) {
      debugPrint("❌ Invalid accuracy: $accuracyError");
      return false;
    }

    try {
      final response = await _retryWithBackoff(
        () => _dio.post('/location/ping', data: ping.toJson()),
        maxRetries: 2,
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } on DioException catch (e) {
      debugPrint("Ping failed: ${e.message}");
      return false;
    } catch (e) {
      debugPrint("Ping failed: $e");
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // SOS — PRIORITY CHANNEL (FIX #6)
  // -------------------------------------------------------------------------
  // Uses _sosDio (dedicated Dio instance) with NO retry queue.
  // SOS fires immediately with aggressive parallel attempts if first fails.
  // -------------------------------------------------------------------------

  Future<SosAlertResult> triggerSosAlert(
    double lat,
    double lng,
    String triggerType, {
    String? touristId,
  }) async {
    final sosCorrelationId = 'SOS-${const Uuid().v4().substring(0, 8)}';
    final userType =
        touristId?.startsWith('GUEST-') == true ? 'guest' : 'authenticated';
    final guestSessionId = touristId?.startsWith('GUEST-') == true ? touristId : null;

    final coordError = Validators.validateCoordinates(lat, lng);
    if (coordError != null) {
      debugPrint('❌ SOS validation failed: $coordError');
      return const SosAlertResult(
        accepted: false,
        dispatched: false,
        status: 'invalid_coordinates',
        dispatchStatus: 'not_sent',
      );
    }

    final triggerTypeError = Validators.validateSosTriggerType(triggerType);
    if (triggerTypeError != null) {
      debugPrint('❌ SOS validation failed: $triggerTypeError');
      return const SosAlertResult(
        accepted: false,
        dispatched: false,
        status: 'invalid_trigger_type',
        dispatchStatus: 'not_sent',
      );
    }

    final guestSessionError =
        Validators.validateGuestSessionId(userType, guestSessionId);
    if (guestSessionError != null) {
      debugPrint('❌ SOS validation failed: $guestSessionError');
      return const SosAlertResult(
        accepted: false,
        dispatched: false,
        status: 'invalid_guest_session',
        dispatchStatus: 'not_sent',
      );
    }

    final payload = {
      'tourist_id': touristId ?? 'UNKNOWN',
      'latitude': lat,
      'longitude': lng,
      'trigger_type': triggerType,
      'timestamp': DateTime.now().toIso8601String(),
      'user_type': userType,
      'guest_session_id': guestSessionId,
    };

    debugPrint(
        '🚨 SOS PRIORITY CHANNEL [CID: $sosCorrelationId] — Firing immediately');

    // Attempt 1: Direct fire, no queue
    try {
      final response = await _sosDio
          .post(
            '/sos/trigger',
            data: payload,
            options: Options(headers: {'X-Correlation-ID': sosCorrelationId}),
          )
          .timeout(const Duration(seconds: 10));

      return _parseSosResponse(response);
    } catch (firstError) {
      debugPrint(
          '⚠️ SOS attempt 1 failed [CID: $sosCorrelationId]: $firstError');
    }

    // Attempt 2: Immediate retry (no backoff — this is life-critical)
    try {
      final response = await _sosDio
          .post(
            '/sos/trigger',
            data: payload,
            options: Options(headers: {'X-Correlation-ID': sosCorrelationId}),
          )
          .timeout(const Duration(seconds: 15));

      return _parseSosResponse(response);
    } catch (secondError) {
      debugPrint(
          '⚠️ SOS attempt 2 failed [CID: $sosCorrelationId]: $secondError');
    }

    // Attempt 3: Last-ditch with extended timeout
    try {
      final response = await _sosDio
          .post(
            '/sos/trigger',
            data: payload,
            options: Options(headers: {'X-Correlation-ID': sosCorrelationId}),
          )
          .timeout(const Duration(seconds: 30));

      return _parseSosResponse(response);
    } catch (finalError) {
      debugPrint(
          '❌ SOS ALL ATTEMPTS FAILED [CID: $sosCorrelationId]: $finalError');
      return const SosAlertResult(
        accepted: false,
        dispatched: false,
        status: 'all_attempts_failed',
        dispatchStatus: 'failed',
      );
    }
  }

  SosAlertResult _parseSosResponse(Response response) {
    final data = response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : <String, dynamic>{};
    final status = data['status']?.toString() ?? 'unknown';
    final dispatch = data['dispatch'] is Map
        ? data['dispatch'] as Map
        : const <String, dynamic>{};
    final dispatchStatus = dispatch['status']?.toString() ?? 'unknown';
    final accepted = response.statusCode == 200 || response.statusCode == 201;
    return SosAlertResult(
      accepted: accepted,
      dispatched: dispatchStatus == 'delivered',
      status: status,
      dispatchStatus: dispatchStatus,
    );
  }

  // -------------------------------------------------------------------------
  // AUTHORITY AUTH
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> registerAuthority(
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/auth/register/authority', data: data);
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ApiException("Authority registration failed: $e");
    }
  }

  Future<Map<String, dynamic>> loginAuthority(
      String email, String password) async {
    try {
      final response = await _dio.post('/auth/login/authority', data: {
        'email': email,
        'password': password,
      });
      final token = response.data['token'];
      final refreshToken = response.data['refresh_token'];
      if (token != null && token is String && token.isNotEmpty) {
        await _secureStorage.saveToken(token);
        if (refreshToken != null) {
          await _secureStorage.saveRefreshToken(refreshToken);
        }
      }
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ApiException("Login failed: $e");
    }
  }

  // -------------------------------------------------------------------------
  // DATA ENDPOINTS
  // -------------------------------------------------------------------------

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
      return ["Uttarakhand", "Meghalaya", "Arunachal Pradesh"];
    }
  }

  Future<List<dynamic>> getDestinationsByState(String state) async {
    try {
      final response = await _dio.get('/destinations/$state');
      return response.data;
    } catch (e) {
      debugPrint("API Error fetching destinations: $e");
      if (state == "Uttarakhand") {
        return [
          {
            "id": "UK_KED_001",
            "name": "Kedarnath Temple",
            "district": "Rudraprayag",
            "altitude_m": 3553,
            "difficulty": "HIGH",
            "connectivity": "POOR"
          },
          {
            "id": "UK_TUN_002",
            "name": "Tungnath Temple",
            "district": "Rudraprayag",
            "altitude_m": 3680,
            "difficulty": "MODERATE",
            "connectivity": "POOR"
          },
          {
            "id": "UK_BAD_003",
            "name": "Badrinath Temple",
            "district": "Chamoli",
            "altitude_m": 3133,
            "difficulty": "MODERATE",
            "connectivity": "MODERATE"
          }
        ];
      }
      return [];
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

  // -------------------------------------------------------------------------
  // EXPONENTIAL BACKOFF WITH JITTER (FIX #4)
  // -------------------------------------------------------------------------
  // Formula: delay = base * 2^attempt + random_jitter
  // Jitter range: 0 to base_delay * 0.5 (decorrelated jitter)
  // This prevents thundering herd / request spike synchronization.
  // -------------------------------------------------------------------------

  Future<Response> _retryWithBackoff(
    Future<Response> Function() task, {
    int maxRetries = 3,
    String? correlationId,
  }) async {
    int retries = 0;
    while (true) {
      try {
        return await task();
      } catch (e) {
        if (retries >= maxRetries) rethrow;

        // Don't retry on client errors (4xx) except 408/429
        if (e is DioException) {
          final status = e.response?.statusCode ?? 0;
          if (status != 0 && status < 500 && status != 408 && status != 429) {
            rethrow;
          }
          // FIX #8: Don't silently retry 429 — let it bubble up as RateLimitException
          if (status == 429) rethrow;
        } else {
          rethrow;
        }

        retries++;
        // FIX #4: base * 2^attempt + random jitter (0 to 50% of base delay)
        final baseDelayMs = 500 * (1 << retries); // 1000, 2000, 4000, ...
        final jitterMs =
            _jitterRng.nextInt((baseDelayMs * 0.5).toInt().clamp(1, 5000));
        final totalDelayMs = baseDelayMs + jitterMs;

        final cid = correlationId ?? '-';
        debugPrint(
            '⚠️ Retry $retries/$maxRetries in ${totalDelayMs}ms (base: ${baseDelayMs}ms + jitter: ${jitterMs}ms) [CID: $cid]');
        await Future.delayed(Duration(milliseconds: totalDelayMs));
      }
    }
  }

  // -------------------------------------------------------------------------
  // GENERIC POST
  // -------------------------------------------------------------------------

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
