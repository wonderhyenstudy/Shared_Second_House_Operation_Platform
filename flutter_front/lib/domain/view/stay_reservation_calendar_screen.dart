/*
 * ==================================================================================
 * [파일 정보]
 * 위치  : lib/domain/view/stay_reservation_calendar_screen.dart
 * 역할  : 숙소 예약 달력 화면 (날짜 범위 선택 → 예약 생성)
 * 사용처 : StayAccommodationDetailScreen 에서 "예약하기" 버튼 탭 시 push
 * ----------------------------------------------------------------------------------
 * [연관 파일]
 * - stay_reservation_controller.dart   : 예약 생성 / 날짜 선택 상태 (Provider)
 * - table_calendar 패키지              : 달력 UI
 * - Spring: StayReservationController  : POST /stay/reservations
 * ----------------------------------------------------------------------------------
 * [기능 목록]
 * - 달력에서 날짜 범위(시작일 ~ 종료일) 선택
 * - 구독 기간 내로 선택 범위 제한 (subscriptionStartDate ~ subscriptionEndDate)
 * - 기존 예약된 날짜 블록 표시 (선택 불가)
 * - 선택 완료 후 예약 생성 요청
 * ==================================================================================
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_front/common/constants/app_colors.dart';
import 'package:flutter_front/common/widget/app_base_layout.dart';
import 'package:flutter_front/features/auth/provider/auth_provider.dart';
import 'package:flutter_front/domain/controller/stay_reservation_controller.dart';

class StayReservationCalendarScreen extends StatefulWidget {
  final int accommodationId;
  final String accommodationName;
  final DateTime? subscriptionStartDate;
  final DateTime? subscriptionEndDate;

  const StayReservationCalendarScreen({
    super.key,
    required this.accommodationId,
    required this.accommodationName,
    this.subscriptionStartDate,
    this.subscriptionEndDate,
  });

  @override
  State<StayReservationCalendarScreen> createState() => _StayReservationCalendarScreenState();
}

class _StayReservationCalendarScreenState extends State<StayReservationCalendarScreen> with WidgetsBindingObserver {

  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  late DateTime _focusedDay;

  DateTime get _calendarFirstDay {
    final today = _normalize(DateTime.now());
    if (widget.subscriptionStartDate != null) {
      final subStart = _normalize(widget.subscriptionStartDate!);
      return subStart.isAfter(today) ? subStart : today;
    }
    return today;
  }

  DateTime get _calendarLastDay {
    if (widget.subscriptionEndDate != null) {
      return _normalize(widget.subscriptionEndDate!);
    }
    return DateTime.now().add(const Duration(days: 365));
  }

  DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    // 달력 포커스를 구독 시작일 또는 오늘 기준으로 초기화
    _focusedDay = _calendarFirstDay;
    // WidgetsBindingObserver 등록 → 앱 생명주기(포그라운드/백그라운드) 변화 감지
    WidgetsBinding.instance.addObserver(this);
    // 첫 프레임 렌더링 후 숙소별 예약 목록 로드 (build 중 Provider 호출 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StayReservationController>().loadAccommodationReservations(widget.accommodationId);
    });
  }

  @override
  void dispose() {
    // 화면이 사라질 때 Observer 해제 (메모리 누수 방지)
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 앱 생명주기 변화 감지 → 포그라운드 복귀 시 예약 목록 자동 갱신
  // 다른 사용자가 앱 사용 중 같은 날짜를 예약한 경우에도 달력에 즉시 반영
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // resumed: 앱이 백그라운드 → 포그라운드로 돌아온 순간
      context.read<StayReservationController>().loadAccommodationReservations(widget.accommodationId);
    }
  }

  // 달력에서 날짜 선택 가능 여부 판단 — false 반환 시 해당 날짜 비활성화(취소선)
  bool _isDayEnabled(DateTime day, StayReservationController ctrl) {
    final d = _normalize(day); // 시간 제거, 날짜만 비교

    // 조건 1: 구독 기간(firstDay ~ lastDay) 밖의 날짜는 선택 불가
    if (d.isBefore(_calendarFirstDay) || d.isAfter(_calendarLastDay)) return false;

    // 조건 2: CONFIRMED 예약 기간 내 날짜 → 선택 불가 (CANCELLED는 다시 선택 가능)
    for (final r in ctrl.accommodationReservations) {
      if (r.status == 'CANCELLED') continue; // 취소된 예약은 재예약 가능 → 건너뜀
      if (r.startDate.isEmpty || r.endDate.isEmpty) continue;
      try {
        final rStart = _normalize(DateTime.parse(r.startDate));
        final rEnd = _normalize(DateTime.parse(r.endDate));
        // d가 기존 예약 기간(rStart ~ rEnd) 안에 있으면 비활성
        if (!d.isBefore(rStart) && !d.isAfter(rEnd)) return false;
      } catch (_) {
        continue; // 날짜 파싱 실패 시 무시
      }
    }

    // 조건 3: 시작일 선택 후, 종료일 선택 중인 상태
    // → 내 선택 시작일 이후 첫 번째 기존 예약 시작일부터는 선택 불가 (dynamicMaxDate 효과)
    if (_rangeStart != null && _rangeEnd == null) {
      final start = _normalize(_rangeStart!);
      DateTime? nextBookedStart; // 내 시작일 이후 가장 빠른 기존 예약 시작일
      for (final r in ctrl.accommodationReservations) {
        if (r.status == 'CANCELLED') continue;
        if (r.startDate.isEmpty) continue;
        try {
          final rStart = _normalize(DateTime.parse(r.startDate));
          if (rStart.isAfter(start)) {
            // 더 이른 예약이 있으면 교체
            if (nextBookedStart == null || rStart.isBefore(nextBookedStart)) {
              nextBookedStart = rStart;
            }
          }
        } catch (_) {
          continue;
        }
      }
      // 다음 예약 시작일과 같거나 이후 날짜는 선택 불가 → 기존 예약 사이에 끼어드는 예약 차단
      if (nextBookedStart != null && !d.isBefore(nextBookedStart)) return false;
    }

    return true; // 위 조건에 걸리지 않으면 선택 가능
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<StayReservationController>();

    return AppBaseLayout(
      title: widget.accommodationName,
      actions: _rangeStart != null
          ? [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: '초기화',
                onPressed: () => setState(() {
                  _rangeStart = null;
                  _rangeEnd = null;
                }),
              ),
            ]
          : null,
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('예약 날짜를 선택해주세요', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          if (widget.subscriptionStartDate != null && widget.subscriptionEndDate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: AppColors.textHint),
                  const SizedBox(width: 6),
                  Text(
                    '구독 기간: ${_fmtDate(widget.subscriptionStartDate!)} ~ ${_fmtDate(widget.subscriptionEndDate!)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TableCalendar(
                firstDay: _calendarFirstDay,
                lastDay: _calendarLastDay,
                focusedDay: _focusedDay,
                locale: 'ko_KR',
                rangeStartDay: _rangeStart,
                rangeEndDay: _rangeEnd,
                rangeSelectionMode: RangeSelectionMode.toggledOn,
                enabledDayPredicate: (day) => _isDayEnabled(day, ctrl),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
                calendarStyle: CalendarStyle(
                  rangeHighlightColor: AppColors.primary.withValues(alpha: 0.12),
                  rangeStartDecoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  rangeEndDecoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  todayDecoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  disabledTextStyle: const TextStyle(
                    color: Color(0xFFCCCCCC),
                    decoration: TextDecoration.lineThrough,
                  ),
                  outsideDaysVisible: false,
                ),
                onRangeSelected: (start, end, focusedDay) {
                  setState(() {
                    _rangeStart = start;
                    _rangeEnd = end;
                    _focusedDay = focusedDay;
                  });
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
              ),
            ),
          ),

          if (_rangeStart != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('선택 기간', style: TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          '${_fmtDate(_rangeStart!)} ~ ${_rangeEnd != null ? _fmtDate(_rangeEnd!) : '종료일 선택'}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ],
                    ),
                    if (_rangeStart != null && _rangeEnd != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '총 ${_rangeEnd!.difference(_rangeStart!).inDays}박',
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          const Spacer(),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_rangeStart != null && _rangeEnd != null && !ctrl.isLoading)
                      ? () => _handleReservation(ctrl)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: ctrl.isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('예약 확정', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleReservation(StayReservationController ctrl) async {
    // Controller에 선택한 날짜 범위 저장 (createReservation에서 사용)
    ctrl.selectDateRange(_rangeStart!, _rangeEnd!);
    // userId는 AuthProvider에서 가져옴 (로그인된 유저 ID)
    final success = await ctrl.createReservation(widget.accommodationId, context.read<AuthProvider>().userId!);

    // 비동기 완료 후 위젯이 아직 트리에 있는지 확인 (없으면 context 사용 불가)
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('예약이 완료되었습니다!'), backgroundColor: AppColors.success),
      );
      // 예약 성공 → 이전 화면(숙소 상세)으로 돌아감
      Navigator.pop(context);
    } else {
      // 예약 실패 (날짜 중복 등) → 에러 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ctrl.errorMessage ?? '예약에 실패했습니다.'), backgroundColor: AppColors.danger),
      );
    }
  }

  String _fmtDate(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
}
