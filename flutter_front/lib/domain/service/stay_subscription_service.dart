/*
 * ==================================================================================
 * [파일 정보]
 * 위치  : lib/domain/service/stay_subscription_service.dart
 * 역할  : 구독 신청 / 조회 API 통신 레이어
 * 사용처 : StayAccommodationController, StaySubscriptionApplyScreen
 * ----------------------------------------------------------------------------------
 * [연관 파일]
 * - stay_accommodation_controller.dart   : getMySubscriptions 호출
 * - stay_subscription_apply_screen.dart  : applySubscription 호출
 * - Spring: SubscriptionsController.java : /subscriptions, /waiting
 * ----------------------------------------------------------------------------------
 * [메서드 목록]
 * - applySubscription()      : 구독 신청 POST /waiting/apply/{leaderId}
 * - getMySubscriptions(id)   : 내 구독 목록 GET /subscriptions/my/{userId}
 * - getMyInvitations(id)     : 내 초대 목록 GET /waiting/my/{userId}
 * ==================================================================================
 */

import 'package:dio/dio.dart';
import 'package:flutter_front/core/api/dio_client.dart';
import 'package:flutter_front/domain/dto/stay_subscription_dto.dart';

class SubscriptionService {
  Dio get _dio => DioClient.instance.dio;

  /// 구독 신청 - POST /waiting/apply/{leaderId}
  /// body 필드 설명:
  ///   - accommodationId     : 신청할 숙소 ID
  ///   - durationMonths      : 구독 개월 수 (1~12개월)
  ///   - memberIdentifiers   : 팀원 username 또는 email 목록 (빈 값 제외 후 전달)
  ///   - startDate           : 희망 구독 시작일 "YYYY-MM-DD" (Spring에서 날짜 겹침 검증)
  Future<void> applySubscription({
    required int leaderId,
    required int accommodationId,
    required int durationMonths,
    required List<String> memberIdentifiers,
    required String startDate, // 희망 구독 시작일 (YYYY-MM-DD)
  }) async {
    await _dio.post(
      '/waiting/apply/$leaderId',
      data: {
        'accommodationId': accommodationId,
        'durationMonths': durationMonths,
        'memberIdentifiers': memberIdentifiers, // 팀원 ID/이메일 목록
        'startDate': startDate,                 // 희망 시작일
      },
    );
  }

  // 숙소별 사용 불가 기간 조회 - GET /subscriptions/accommodation/{accommodationId}
  // 반환값: PENDING/ACTIVE 상태인 구독의 startDate~endDate 기간 목록
  Future<List<SubscriptionDateRangeDto>> getSubscriptionBlockedPeriods(int accommodationId) async {
    final response = await _dio.get('/subscriptions/accommodation/$accommodationId');
    // 서버 오류나 빈 데이터로 List가 아닌 값이 올 수 있으므로 방어 처리
    if (response.data is! List) return [];
    return (response.data as List)
        .map((e) => SubscriptionDateRangeDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 내 구독 목록 조회 - GET /subscriptions/my/{userId}
  /// 반환값: 내가 대표자 또는 팀원으로 포함된 모든 구독 (상태 무관)
  Future<List<StaySubscriptionDto>> getMySubscriptions(int userId) async {
    final response = await _dio.get('/subscriptions/my/$userId');
    // 빈 응답이나 예외 상황에 List가 아닌 값 올 수 있으므로 방어 처리
    if (response.data is! List) return [];
    return (response.data as List)
        .map((e) => StaySubscriptionDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 내 초대 목록 조회 - GET /waiting/my/{userId}
  /// 팀원으로 초대받았지만 아직 수락/거절하지 않은 대기 목록
  Future<List<dynamic>> getMyInvitations(int userId) async {
    final response = await _dio.get('/waiting/my/$userId');
    return response.data as List;
  }
}
