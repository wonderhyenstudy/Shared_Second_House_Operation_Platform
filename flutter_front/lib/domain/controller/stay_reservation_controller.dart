/*
 * ==================================================================================
 * [파일 정보]
 * 위치  : lib/domain/controller/stay_reservation_controller.dart
 * 역할  : 숙소 예약 상태 관리 (ChangeNotifier + Provider 패턴)
 * 사용처 : StayMyReservationScreen, StayReservationCalendarScreen
 * ----------------------------------------------------------------------------------
 * [연관 파일]
 * - stay_reservation_service.dart       : API 호출
 * - stay_reservation_dto.dart           : 예약 모델
 * - config/app_router.dart              : ChangeNotifierProvider 등록
 * ----------------------------------------------------------------------------------
 * [상태 목록]
 * - reservations               : 내 예약 목록
 * - accommodationReservations  : 숙소별 예약 목록 (달력 날짜 블록용)
 * - selectedStartDate / selectedEndDate : 선택된 예약 날짜 범위
 * ----------------------------------------------------------------------------------
 * [메서드 목록]
 * - loadMyReservations()              : 내 예약 목록 조회
 * - loadAccommodationReservations(id) : 숙소별 예약 목록 조회
 * - createReservation(accommodationId): 예약 생성 (선택 날짜 기반)
 * - cancelReservation(id)             : 예약 취소
 * - selectDateRange(start, end)       : 날짜 범위 선택
 * - clearDateRange()                  : 날짜 선택 초기화
 * ==================================================================================
 */

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_front/domain/dto/stay_reservation_dto.dart';
import 'package:flutter_front/domain/service/stay_reservation_service.dart';

class StayReservationController extends ChangeNotifier {
  final StayReservationService _service = StayReservationService();

  List<StayReservationDto> reservations = [];
  List<StayReservationDto> accommodationReservations = []; // 숙소별 예약 (달력 날짜 블록용)
  bool isLoading = false;
  String? errorMessage;

  DateTime? selectedStartDate;
  DateTime? selectedEndDate;

  // 내 예약 목록 로드 — isLoading 상태로 로딩 스피너 제어
  Future<void> loadMyReservations(int userId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners(); // isLoading = true 상태를 View에 전달 → 스피너 표시

    try {
      reservations = await _service.getMyReservations(userId);
    } catch (e) {
      errorMessage = '예약 목록을 불러오지 못했습니다.';
      debugPrint('❌ [예약 컨트롤러] $e');
    }

    isLoading = false;
    notifyListeners(); // isLoading = false → 스피너 숨김, 목록 표시
  }

  // 숙소별 예약 목록 로드 — 달력 날짜 비활성화에 사용
  // 로딩 스피너 없이 조용히 업데이트 (달력 갱신은 UX 방해 없이 처리)
  Future<void> loadAccommodationReservations(int accommodationId) async {
    try {
      accommodationReservations = await _service.getAccommodationReservations(accommodationId);
      notifyListeners(); // 예약 목록 갱신 → 달력 자동 재렌더링
    } catch (e) {
      debugPrint('❌ [숙소별 예약 로드] $e');
    }
  }

  // 예약 생성 — true 반환 시 성공, false 반환 시 실패
  Future<bool> createReservation(int accommodationId, int userId) async {
    // 날짜가 선택되지 않은 상태에서 호출되면 즉시 false 반환
    if (selectedStartDate == null || selectedEndDate == null) return false;

    isLoading = true;
    notifyListeners();

    try {
      // 선택된 날짜를 "YYYY-MM-DD" 문자열로 변환해 요청 DTO 생성
      final req = StayReservationRequestDto(
        accommodationId: accommodationId,
        userId: userId,
        startDate: _formatDate(selectedStartDate!),
        endDate: _formatDate(selectedEndDate!),
      );
      final result = await _service.createReservation(req);
      // 예약 성공 → 로컬 목록에 즉시 추가 (전체 재조회 없이 반영)
      reservations.add(result);
      // 달력도 최신 예약 현황으로 갱신 (방금 예약한 날짜 비활성화)
      await loadAccommodationReservations(accommodationId);
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // DioException이면 서버 응답에서 에러 메시지 추출, 아니면 기본 메시지
      final data = (e is DioException) ? e.response?.data : null;
      errorMessage = (data is Map && data['message'] != null) ? data['message'] : '예약에 실패했습니다.';
      debugPrint('❌ [예약 생성] $e');
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // 예약 취소 — 서버 API 호출 후 로컬 상태만 업데이트 (전체 재조회 없음)
  Future<bool> cancelReservation(int id, int userId) async {
    try {
      await _service.cancelReservation(id, userId);
      // 취소 성공 → 해당 항목만 CANCELLED로 교체 (목록 전체 재조회 없이 즉시 반영)
      final idx = reservations.indexWhere((r) => r.id == id);
      if (idx != -1) {
        // 불변 패턴: 기존 DTO를 status만 바꿔서 새 DTO로 교체
        reservations[idx] = StayReservationDto(
          id: reservations[idx].id,
          accommodationId: reservations[idx].accommodationId,
          accommodationName: reservations[idx].accommodationName,
          accommodationAddress: reservations[idx].accommodationAddress,
          startDate: reservations[idx].startDate,
          endDate: reservations[idx].endDate,
          status: 'CANCELLED', // 상태만 변경
        );
      }
      notifyListeners(); // UI 자동 갱신 (취소 배지 즉시 표시)
      return true;
    } catch (e) {
      final data = (e is DioException) ? e.response?.data : null;
      errorMessage = (data is Map && data['message'] != null) ? data['message'] : '예약 취소에 실패했습니다.';
      debugPrint('❌ [예약 취소] $e');
      notifyListeners();
      return false;
    }
  }

  // 달력에서 날짜 범위 선택 → Controller에 저장 (createReservation에서 사용)
  void selectDateRange(DateTime start, DateTime end) {
    selectedStartDate = start;
    selectedEndDate = end;
    notifyListeners();
  }

  // 날짜 선택 초기화 (달력 리셋)
  void clearDateRange() {
    selectedStartDate = null;
    selectedEndDate = null;
    notifyListeners();
  }

  // DateTime → "YYYY-MM-DD" 문자열 변환 (Spring LocalDate 포맷)
  // padLeft(2,'0'): 1자리 월/일을 두 자리로 맞춤 (예: 6 → 06)
  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
