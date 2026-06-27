/*
 * ==================================================================================
 * [파일 정보]
 * 위치  : lib/domain/view/stay_my_reservation_screen.dart
 * 역할  : 내 예약 목록 화면 (예약 카드 + 취소 기능)
 * 사용처 : app_router.dart 에서 라우팅
 * ----------------------------------------------------------------------------------
 * [연관 파일]
 * - stay_reservation_controller.dart  : 예약 목록 상태 (Provider)
 * - stay_reservation_dto.dart         : 예약 모델
 * - Spring: StayReservationController : GET /stay/reservations
 * ----------------------------------------------------------------------------------
 * [기능 목록]
 * - 내 예약 목록 조회 및 표시
 * - 예약 상태별 표시 (CONFIRMED / CANCELLED)
 * - 예약 취소 버튼 (취소된 예약은 버튼 비활성)
 * ==================================================================================
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_front/common/constants/app_colors.dart';
import 'package:flutter_front/common/widget/app_base_layout.dart';
import 'package:flutter_front/common/widget/common_button.dart';
import 'package:flutter_front/features/auth/provider/auth_provider.dart';
import 'package:flutter_front/domain/controller/stay_reservation_controller.dart';
import 'package:flutter_front/domain/dto/stay_reservation_dto.dart';

class StayMyReservationScreen extends StatefulWidget {
  const StayMyReservationScreen({super.key});

  @override
  State<StayMyReservationScreen> createState() => _StayMyReservationScreenState();
}

class _StayMyReservationScreenState extends State<StayMyReservationScreen> {
  @override
  void initState() {
    super.initState();
    // 첫 프레임 렌더링 완료 후 데이터 로드 (build() 실행 중 Provider 접근 오류 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StayReservationController>().loadMyReservations(
        context.read<AuthProvider>().userId!, // 로그인된 유저 ID로 내 예약 조회
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // context.watch: Controller 상태가 바뀔 때마다 이 위젯 자동 재빌드
    final ctrl = context.watch<StayReservationController>();

    return AppBaseLayout(
      title: '내 예약 목록',
      body: ctrl.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary)) // 로딩 중
          : ctrl.reservations.isEmpty
              ? _buildEmpty()  // 예약 없음 안내
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: ctrl.reservations.length,
                  // Spring 서버에서 정렬된 순서대로 표시 (다가오는→취소됨→지난 예약)
                  itemBuilder: (_, index) => _buildCard(ctrl, ctrl.reservations[index]),
                ),
    );
  }

  Widget _buildEmpty() => const Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.calendar_today_outlined, size: 56, color: AppColors.textHint),
      SizedBox(height: 16),
      Text('예약 내역이 없습니다.', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
    ]),
  );

  Widget _buildCard(StayReservationController ctrl, StayReservationDto item) {
    // 상태 판단: DB에는 CONFIRMED / CANCELLED 두 가지만 존재
    // "지난 예약" / "미래 예약"은 프론트에서 날짜 비교로 구분
    final isCancelled = item.isCancelled;                              // status == 'CANCELLED'
    final isPast = !isCancelled && _isPastReservation(item.endDate);   // 종료일이 오늘 이전
    final isFuture = !isCancelled && !isPast && _isFutureReservation(item.startDate); // 시작일이 오늘 이후

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.accommodationName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: (isCancelled || isPast) ? AppColors.textHint : AppColors.textPrimary,
                    ),
                  ),
                ),
                _statusBadge(item.status, item.endDate),
              ],
            ),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textHint),
              const SizedBox(width: 4),
              Expanded(child: Text(item.accommodationAddress, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.calendar_month_outlined, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                '${item.startDate} ~ ${item.endDate}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isCancelled
                      ? AppColors.textHint
                      : isPast
                          ? const Color(0xFF92400E)
                          : AppColors.primary,
                ),
              ),
            ]),
            if (isFuture) ...[
              const SizedBox(height: 12),
              CommonButton(
                label: '예약 취소',
                type: ButtonType.danger,
                onTap: () => _confirmCancel(ctrl, item.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 상태 배지 — DB 상태(CONFIRMED/CANCELLED)와 날짜 비교 결과를 조합해 배지 결정
  Widget _statusBadge(String status, String endDate) {
    if (status == 'CANCELLED') {
      // DB에 명시적으로 취소된 상태
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(20)),
        child: const Text('취소됨', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.disabledText)),
      );
    }
    if (_isPastReservation(endDate)) {
      // CONFIRMED이지만 종료일이 오늘 이전 → "지난 예약" (프론트에서 날짜 비교로 판단)
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(20)),
        child: const Text('지난 예약', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
      );
    }
    // CONFIRMED이고 종료일이 오늘 이후 → "예약 확정"
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const BoxDecoration(color: Color(0xFFE8F5E9), borderRadius: BorderRadius.all(Radius.circular(20))),
      child: const Text('예약 확정', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.success)),
    );
  }

  // 종료일이 현재 시각 이전이면 지난 예약
  bool _isPastReservation(String endDate) {
    final end = DateTime.tryParse(endDate);
    return end != null && end.isBefore(DateTime.now());
  }

  // 시작일이 현재 시각 이후이면 미래 예약 (취소 버튼 표시 조건)
  bool _isFutureReservation(String startDate) {
    final start = DateTime.tryParse(startDate);
    return start != null && start.isAfter(DateTime.now());
  }

  // 취소 확인 다이얼로그 → 확인 시 API 호출
  Future<void> _confirmCancel(StayReservationController ctrl, int id) async {
    // showDialog: 사용자 선택을 기다리는 비동기 다이얼로그, 결과는 bool?
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('예약 취소', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text('예약을 취소하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('아니요')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('취소하기', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    // 다이얼로그에서 "취소하기" 선택 + 위젯이 아직 트리에 있을 때만 처리
    if (confirmed == true && mounted) {
      final success = await ctrl.cancelReservation(id, context.read<AuthProvider>().userId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? '예약이 취소되었습니다.' : ctrl.errorMessage ?? '취소에 실패했습니다.'),
          backgroundColor: success ? AppColors.success : AppColors.danger,
        ));
      }
    }
  }
}
