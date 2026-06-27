/*
 * ==================================================================================
 * [파일 정보]
 * 위치  : lib/domain/view/stay_my_subscription_screen.dart
 * 역할  : 내 구독 목록 화면 (구독 카드 + 채팅/예약하기 버튼)
 * 사용처 : app_router.dart → '/my/subscriptions' 라우트
 * ----------------------------------------------------------------------------------
 * [연관 파일]
 * - stay_subscription_controller.dart      : 구독 목록 상태 (Provider)
 * - stay_subscription_dto.dart             : 구독 모델
 * - stay_reservation_calendar_screen.dart  : 예약하기 버튼 이동
 * - Spring: SubscriptionsController.java   : GET /subscriptions/my/{userId}
 * ----------------------------------------------------------------------------------
 * [기능 목록]
 * - 내 구독 목록 조회 및 표시
 * - 구독 상태별 배지 (ACTIVE / PENDING / EXPIRED / CANCELLED)
 * - ACTIVE 구독만 채팅 + 예약하기 버튼 표시
 * ==================================================================================
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_front/common/constants/app_colors.dart';
import 'package:flutter_front/common/widget/app_base_layout.dart';
import 'package:flutter_front/features/auth/provider/auth_provider.dart';
import 'package:flutter_front/domain/controller/stay_subscription_controller.dart';
import 'package:flutter_front/domain/dto/stay_subscription_dto.dart';
import 'package:flutter_front/domain/view/stay_reservation_calendar_screen.dart';

class StayMySubscriptionScreen extends StatefulWidget {
  const StayMySubscriptionScreen({super.key});

  @override
  State<StayMySubscriptionScreen> createState() => _StayMySubscriptionScreenState();
}

class _StayMySubscriptionScreenState extends State<StayMySubscriptionScreen> {
  @override
  void initState() {
    super.initState();
    // 첫 프레임 완료 후 구독 목록 로드 (build 중 Provider 호출 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StaySubscriptionController>().loadMySubscriptions(
        context.read<AuthProvider>().userId!,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // context.watch: Controller 상태 변경 시 자동 재빌드
    final ctrl = context.watch<StaySubscriptionController>();

    return AppBaseLayout(
      title: '내 구독 목록',
      body: ctrl.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ctrl.subscriptions.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: ctrl.subscriptions.length,
                  itemBuilder: (_, i) => _buildCard(ctrl, ctrl.subscriptions[i]),
                ),
    );
  }

  Widget _buildEmpty() => const Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.home_outlined, size: 56, color: AppColors.textHint),
      SizedBox(height: 16),
      Text('구독 내역이 없습니다.', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
    ]),
  );

  Widget _buildCard(StaySubscriptionController ctrl, StaySubscriptionDto sub) {
    // Controller의 accommodationCache에서 숙소 정보 꺼냄 (별도 API 호출 없이 캐시 활용)
    // null이면 숙소 정보 아직 로딩 중 → "숙소 정보 로딩 중..." 표시
    final accom = ctrl.accommodationCache[sub.accommodationId];

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
                    accom?.name ?? '숙소 정보 로딩 중...',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ),
                _statusBadge(sub.status),
              ],
            ),
            if (accom != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textHint),
                const SizedBox(width: 4),
                Expanded(child: Text(accom.address, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ],
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.calendar_month_outlined, size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Expanded(child: Text('${sub.startDate} ~ ${sub.endDate}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.schedule_outlined, size: 14, color: AppColors.textHint),
              const SizedBox(width: 4),
              Expanded(child: Text('구독 기간: ${sub.durationMonths}개월', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
            ]),
            // ACTIVE 구독만 채팅 + 예약하기 버튼 표시
            // PENDING/EXPIRED/CANCELLED는 버튼 없음 (구독 중인 사람만 서비스 이용 가능)
            if (sub.isActive) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        // TODO: 채팅 팀원 라우트 연동 시 Navigator.push 로 교체
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('채팅 기능은 준비 중입니다.')),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('채팅', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StayReservationCalendarScreen(
                            accommodationId: sub.accommodationId,
                            accommodationName: accom?.name ?? '',
                            // 구독 시작일·종료일을 달력 화면에 전달 → minDate / maxDate로 사용
                            subscriptionStartDate: DateTime.tryParse(sub.startDate),
                            subscriptionEndDate: DateTime.tryParse(sub.endDate),
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('예약하기', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 구독 상태 배지 — DB 상태값(ACTIVE/PENDING/EXPIRED/CANCELLED)을 한국어 배지로 표시
  Widget _statusBadge(String status) {
    switch (status) {
      case 'ACTIVE':   // 관리자 승인 완료 → 구독 중
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: const BoxDecoration(color: Color(0xFFE8F5E9), borderRadius: BorderRadius.all(Radius.circular(20))),
          child: const Text('구독 중', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.success)),
        );
      case 'PENDING':  // 팀원 동의 대기 또는 관리자 승인 대기
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: const BoxDecoration(color: Color(0xFFFFF8E6), borderRadius: BorderRadius.all(Radius.circular(20))),
          child: const Text('승인 대기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB07D1A))),
        );
      default:         // EXPIRED(구독 기간 만료) 또는 CANCELLED(취소됨)
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: const BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.all(Radius.circular(20))),
          child: Text(
            status == 'EXPIRED' ? '만료됨' : '취소됨',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.disabledText),
          ),
        );
    }
  }
}
