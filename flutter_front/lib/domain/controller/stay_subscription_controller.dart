/*
 * ==================================================================================
 * [파일 정보]
 * 위치  : lib/domain/controller/stay_subscription_controller.dart
 * 역할  : 내 구독 목록 상태 관리 (Provider)
 * 사용처 : StayMySubscriptionScreen
 * ----------------------------------------------------------------------------------
 * [연관 파일]
 * - stay_subscription_service.dart     : 구독 목록 API 호출
 * - stay_accommodation_service.dart    : 숙소 이름/주소 병렬 조회
 * - stay_subscription_dto.dart         : 구독 모델
 * - stay_accommodation_dto.dart        : 숙소 모델 (이름/주소용)
 * ----------------------------------------------------------------------------------
 * [메서드 목록]
 * - loadMySubscriptions(userId) : 구독 목록 + 숙소 정보 병렬 조회
 * ==================================================================================
 */

import 'package:flutter/foundation.dart';
import 'package:flutter_front/domain/dto/stay_accommodation_dto.dart';
import 'package:flutter_front/domain/dto/stay_subscription_dto.dart';
import 'package:flutter_front/domain/service/stay_accommodation_service.dart';
import 'package:flutter_front/domain/service/stay_subscription_service.dart';

class StaySubscriptionController extends ChangeNotifier {
  final SubscriptionService _service = SubscriptionService();
  final StayAccommodationService _accomService = StayAccommodationService();

  List<StaySubscriptionDto> subscriptions = [];
  final Map<int, StayAccommodationDto> accommodationCache = {};
  bool isLoading = false;
  String? errorMessage;

  Future<void> loadMySubscriptions(int userId) async {
    isLoading = true;     // 스피너 표시 시작
    errorMessage = null;
    notifyListeners();    // UI에 로딩 상태 알림

    try {
      // 1단계: 내 구독 목록 조회 (JWT 기반으로 본인 구독만 반환)
      subscriptions = await _service.getMySubscriptions(userId);

      // 2단계: 구독 목록에서 숙소 ID를 중복 없이 추출 (Set으로 dedup)
      // toSet(): 같은 숙소에 구독이 여러 개 있어도 API 중복 호출 방지
      final ids = subscriptions.map((s) => s.accommodationId).toSet();

      // 3단계: 각 숙소 정보를 Future.wait로 동시에 조회 (순차 조회보다 빠름)
      // accommodationCache[id]: View에서 sub.accommodationId로 바로 접근 → 별도 API 호출 불필요
      await Future.wait(ids.map((id) async {
        try {
          accommodationCache[id] = await _accomService.getAccommodation(id);
        } catch (_) {
          // 숙소 조회 실패 시 해당 숙소만 캐시에서 빠짐 → View에서 null 체크로 "로딩 중" 표시
        }
      }));
    } catch (_) {
      errorMessage = '구독 목록을 불러오지 못했습니다.';
    } finally {
      isLoading = false;  // 스피너 해제
      notifyListeners();  // UI에 최종 상태 알림 (구독 목록 + 숙소 캐시 반영)
    }
  }
}
