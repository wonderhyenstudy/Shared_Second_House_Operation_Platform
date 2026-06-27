/*
 * ==================================================================================
 * [파일 정보]
 * 위치  : lib/domain/view/stay_subscription_apply_screen.dart
 * 역할  : 구독 신청 화면 (대표자 + 팀원 입력 → 구독 신청 요청)
 * 사용처 : StayAccommodationDetailScreen 에서 "구독 신청하기" 버튼 탭 시 push
 * ----------------------------------------------------------------------------------
 * [연관 파일]
 * - stay_subscription_service.dart      : applySubscription(), getSubscriptionBlockedPeriods() 호출
 * - stay_accommodation_dto.dart         : 숙소 정보 props
 * - stay_constants.dart                 : kMonthOptionValues, monthOptionLabel
 * - stay_subscription_dto.dart          : SubscriptionDateRangeDto
 * - table_calendar 패키지               : 달력 UI
 * - Spring: SubscriptionsController.java : POST /waiting/apply/{leaderId}
 * - Spring: SubscriptionsUserController : GET /api/subscriptions/accommodation/{id}
 * ----------------------------------------------------------------------------------
 * [기능 목록]
 * - 숙소 정보 카드 표시 (이름, 주소, 월세)
 * - 대표자 자동 설정 (로그인한 사용자 userId)
 * - 팀원 추가 / 삭제 (TextEditingController 동적 관리)
 * - 계약 개월수 드롭다운 선택
 * - [날짜 검증 추가] 사용 불가 기간 / 신청 가능 기간 안내 박스
 * - [날짜 검증 추가] 달력에서 희망 시작일 선택 (오늘 이전 + 사용 불가 날짜 비활성화)
 * - [날짜 검증 추가] 실시간 겹침 감지 + 경고 문구 + 신청 버튼 비활성화
 * - 팀당 월세 실시간 계산 (_calcTeamPrice)
 * - 구독 신청 → 완료 시 이전 화면으로 pop
 * ----------------------------------------------------------------------------------
 * [파일 흐름과 순서]
 * 진입(accommodation props) → 대표자 자동 설정 + 사용 불가 기간 조회
 * → 팀원 추가 → TextEditingController 생성 → 팀 인원 증가 → 가격 재계산
 * → 사용 불가 기간 박스 + 신청 가능 기간 박스 표시
 * → TableCalendar에서 시작일 선택 → 겹침 감지 → 버튼 활성/비활성
 * → "구독 신청하기" → _handleSubmit() → POST /waiting/apply/{leaderId}
 * → 성공: SnackBar + pop / 실패: 에러 SnackBar
 * ==================================================================================
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_front/common/constants/app_colors.dart';
import 'package:flutter_front/common/constants/stay_constants.dart';
import 'package:flutter_front/common/widget/app_base_layout.dart';
import 'package:flutter_front/common/widget/common_button.dart';
import 'package:flutter_front/features/auth/provider/auth_provider.dart';
import 'package:flutter_front/domain/dto/stay_accommodation_dto.dart';
import 'package:flutter_front/domain/dto/stay_subscription_dto.dart';
import 'package:flutter_front/domain/service/stay_subscription_service.dart';
import 'package:flutter_front/util/price_calculator.dart';

class StaySubscriptionApplyScreen extends StatefulWidget {
  final StayAccommodationDto accommodation;

  const StaySubscriptionApplyScreen({super.key, required this.accommodation});

  @override
  State<StaySubscriptionApplyScreen> createState() => _StaySubscriptionApplyScreenState();
}

class _StaySubscriptionApplyScreenState extends State<StaySubscriptionApplyScreen> {
  final SubscriptionService _service = SubscriptionService();

  int get _leaderId => context.read<AuthProvider>().userId!;

  final List<TextEditingController> _memberControllers = [];
  int _durationMonths = 1;
  bool _isLoading = false;

  // [날짜 검증 추가] 희망 시작일 + 사용 불가 기간 목록 + 달력 포커스
  DateTime? _startDate;
  List<SubscriptionDateRangeDto> _blockedPeriods = [];
  bool _periodsLoaded = false;
  late DateTime _focusedDay;

  // 오늘 날짜 (시간 제거)
  DateTime get _today => DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  // 종료일 자동 계산 — 시작일 + 계약 개월수
  // DateTime 생성자에 month+N을 직접 넣으면 자동으로 다음 해로 넘어감 (예: month=13 → 내년 1월)
  DateTime? get _endDate {
    if (_startDate == null) return null;
    return DateTime(_startDate!.year, _startDate!.month + _durationMonths, _startDate!.day);
  }

  // 사용 불가 기간의 모든 날짜를 Set으로 변환 — 달력에서 빠르게 비활성화 여부 조회
  // Set 사용 이유: contains() 연산이 O(1)로 빠름 (List는 O(n))
  Set<DateTime> get _blockedDateSet {
    final Set<DateTime> dates = {};
    for (final p in _blockedPeriods) {
      if (p.startDate.isEmpty || p.endDate.isEmpty) continue;
      try {
        DateTime cur = DateTime.parse(p.startDate);
        final end = DateTime.parse(p.endDate);
        // 시작일부터 종료일 하루 전까지 모든 날짜를 Set에 추가 (종료일 당일 제외 → 경계 처리)
        while (cur.isBefore(end)) {
          dates.add(DateTime(cur.year, cur.month, cur.day)); // 시간 제거 후 추가
          cur = cur.add(const Duration(days: 1));
        }
      } catch (_) {
        continue; // 날짜 파싱 실패 시 무시
      }
    }
    return dates;
  }

  // 선택 기간이 사용 불가 기간과 겹치는지 실시간 체크 (getter → _startDate 변경 시 자동 재계산)
  // 겹침 조건: blockedStart < newEnd AND blockedEnd > newStart
  // → 경계가 맞닿는 경우(예: 내 종료일 = 기존 시작일)는 겹침 아님
  bool get _hasDateConflict {
    if (_startDate == null || _endDate == null) return false;
    final startStr = _fmtDateStr(_startDate!);
    final endStr = _fmtDateStr(_endDate!);
    // any(): 하나라도 겹치는 기간이 있으면 true
    return _blockedPeriods.any(
      (p) => p.startDate.compareTo(endStr) < 0 && p.endDate.compareTo(startStr) > 0,
    );
  }

  // 신청 가능 기간 자동 계산 — 사용 불가 기간 사이의 빈 구간을 도출
  // 예) 불가: [3/1~4/1, 5/1~6/1] → 가능: [오늘~3/1, 4/1~5/1, 6/1~제한없음]
  List<Map<String, String?>> get _availableWindows {
    final todayStr = _fmtDateStr(_today);
    // 사용 불가 기간이 없으면 오늘부터 제한 없음
    if (_blockedPeriods.isEmpty) return [{'from': todayStr, 'to': null}];
    // 시작일 기준 오름차순 정렬 (... 스프레드로 원본 불변)
    final sorted = [..._blockedPeriods]..sort((a, b) => a.startDate.compareTo(b.startDate));
    final List<Map<String, String?>> windows = [];
    // 오늘 ~ 첫 번째 사용 불가 시작일 사이에 빈 공간이 있으면 가능 기간으로 추가
    if (sorted.first.startDate.compareTo(todayStr) > 0) {
      windows.add({'from': todayStr, 'to': sorted.first.startDate});
    }
    // 연속된 사용 불가 기간 사이의 빈 구간을 가능 기간으로 추가
    for (int i = 0; i < sorted.length - 1; i++) {
      if (sorted[i].endDate.compareTo(sorted[i + 1].startDate) < 0) {
        windows.add({'from': sorted[i].endDate, 'to': sorted[i + 1].startDate});
      }
    }
    // 마지막 사용 불가 기간 이후는 제한 없음 (to: null → "제한 없음" 표시)
    windows.add({'from': sorted.last.endDate, 'to': null});
    return windows;
  }

  @override
  void initState() {
    super.initState();
    _focusedDay = _today;
    _fetchBlockedPeriods();
  }

  // [날짜 검증 추가] 사용 불가 기간 조회
  Future<void> _fetchBlockedPeriods() async {
    try {
      final periods = await _service.getSubscriptionBlockedPeriods(widget.accommodation.id);
      if (mounted) {
        setState(() {
          _blockedPeriods = periods;
          _periodsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _periodsLoaded = true);
    }
  }

  @override
  void dispose() {
    for (final c in _memberControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addMember() {
    final ctrl = TextEditingController();
    ctrl.addListener(() => setState(() {}));
    setState(() => _memberControllers.add(ctrl));
  }

  void _removeMember(int index) {
    setState(() {
      _memberControllers[index].dispose();
      _memberControllers.removeAt(index);
    });
  }

  // 구독 신청 제출 — 입력값 검증 후 API 호출
  Future<void> _handleSubmit() async {
    if (_startDate == null) return;
    // TextEditingController 목록에서 실제 입력된 값만 추출 (빈 칸 제외)
    final memberIds = _memberControllers
        .map((c) => c.text.trim())
        .where((id) => id.isNotEmpty)
        .toList();

    setState(() => _isLoading = true); // 버튼 로딩 상태로 변경

    try {
      await _service.applySubscription(
        leaderId: _leaderId,                    // 로그인 유저 = 대표자
        accommodationId: widget.accommodation.id,
        durationMonths: _durationMonths,
        memberIdentifiers: memberIds,           // 팀원 아이디/이메일 목록
        startDate: _fmtDateStr(_startDate!),   // 희망 시작일 "YYYY-MM-DD" 전달
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('구독 신청이 완료됐어요! 관리자 승인을 기다려주세요.'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context); // 성공 → 이전 화면(숙소 상세)으로 복귀
      }
    } catch (e) {
      // 실패 원인: 없는 팀원 ID, 날짜 겹침, 중복 구독 등
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('구독 신청에 실패했어요. 다시 시도해주세요.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      // 성공/실패 관계없이 로딩 상태 해제
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 달력 날짜 선택 가능 여부 — 오늘 이전 또는 사용 불가 날짜면 false
  bool _isDayEnabled(DateTime day) {
    final d = DateTime(day.year, day.month, day.day); // 시간 제거
    if (d.isBefore(_today)) return false;             // 오늘 이전 비활성
    return !_blockedDateSet.contains(d);              // 사용 불가 Set에 있으면 비활성
  }

  // YYYY-MM-DD 포맷 헬퍼
  String _fmtDateStr(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final item = widget.accommodation;
    // 신청 버튼 활성 조건: 시작일이 선택되었고 날짜 겹침이 없어야 함
    final canSubmit = _startDate != null && !_hasDateConflict;

    return AppBaseLayout(
      title: '구독 신청',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 숙소 정보 카드
            _buildAccommodationInfo(item),
            const SizedBox(height: 24),

            // 대표자 ID
            _buildSectionTitle('대표자 ID'),
            const SizedBox(height: 8),
            _buildReadonlyField('$_leaderId', hint: '※ 로그인한 유저가 대표자로 자동 설정됩니다.'),
            const SizedBox(height: 20),

            // 팀원 아이디 또는 이메일 목록
            _buildSectionTitle('함께할 팀원 아이디 또는 이메일'),
            const SizedBox(height: 8),
            ..._memberControllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          hintText: '팀원 ${index + 1} 아이디 또는 이메일 입력',
                          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _removeMember(index),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.close, size: 18, color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              );
            }),
            CommonButton(
              label: '+ 팀원 추가',
              type: ButtonType.secondary,
              icon: null,
              onTap: _addMember,
            ),
            const SizedBox(height: 24),

            // 계약 개월수
            _buildSectionTitle('계약 개월수'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<int>(
                value: _durationMonths,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: kMonthOptionValues
                    .map((n) => DropdownMenuItem(value: n, child: Text(monthOptionLabel(n))))
                    .toList(),
                onChanged: (v) => setState(() => _durationMonths = v!),
              ),
            ),
            const SizedBox(height: 24),

            // [날짜 검증 추가] 희망 구독 시작일
            _buildSectionTitle('희망 구독 시작일'),
            const SizedBox(height: 12),

            // [날짜 검증 추가] 기간 현황 안내 (달력 바로 위)
            _buildPeriodInfo(),
            const SizedBox(height: 12),

            // [날짜 검증 추가] 달력
            _buildCalendar(),

            if (_startDate != null && _endDate != null) ...[
              const SizedBox(height: 8),
              Text(
                '선택한 구독 기간: ${_fmtDateStr(_startDate!)} ~ ${_fmtDateStr(_endDate!)}',
                style: const TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
            ],
            if (_hasDateConflict) ...[
              const SizedBox(height: 4),
              const Text(
                '⚠ 선택한 기간이 기존 구독과 겹칩니다. 위 신청 가능 기간을 확인해주세요.',
                style: TextStyle(fontSize: 12, color: Color(0xFFC05000), fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 24),

            // 구독 요약
            _buildPriceSummary(item),
            const SizedBox(height: 32),

            // 신청 버튼 — 날짜 미선택 또는 겹침 시 비활성화
            CommonButton(
              label: '구독 신청하기',
              type: canSubmit ? ButtonType.primary : ButtonType.disabled,
              isLoading: _isLoading,
              onTap: canSubmit ? _handleSubmit : null,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // [날짜 검증 추가] ❌사용불가기간 + ✅신청가능기간 안내 박스
  Widget _buildPeriodInfo() {
    if (!_periodsLoaded) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 사용 불가 기간 (있을 때만 표시)
        if (_blockedPeriods.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8F0),
              border: Border.all(color: const Color(0xFFF5C6A0)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '❌ 사용 불가 기간',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFC05000)),
                ),
                const SizedBox(height: 8),
                ...([..._blockedPeriods]..sort((a, b) => a.startDate.compareTo(b.startDate))).map((p) {
                  final label = p.status == 'ACTIVE' ? '(구독 중)' : '(승인 대기)';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${p.startDate} ~ ${p.endDate}  $label',
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 신청 가능 기간
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F8EC),
            border: Border.all(color: const Color(0xFFC6E0A0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '✅ 신청 가능 기간',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3B6D11)),
              ),
              const SizedBox(height: 8),
              ..._availableWindows.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${w['from']} ~ ${w['to'] ?? '제한 없음'}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              )),
            ],
          ),
        ),
      ],
    );
  }

  // [날짜 검증 추가] 달력 — 예약 화면과 동일한 스타일 적용
  Widget _buildCalendar() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: TableCalendar(
          firstDay: _today,
          lastDay: DateTime(_today.year + 2, _today.month, _today.day),
          focusedDay: _focusedDay,
          locale: 'ko_KR',
          selectedDayPredicate: (day) {
            if (_startDate == null) return false;
            return day.year == _startDate!.year &&
                day.month == _startDate!.month &&
                day.day == _startDate!.day;
          },
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _startDate = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
              _focusedDay = focusedDay;
            });
          },
          enabledDayPredicate: _isDayEnabled,
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            selectedDecoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            disabledTextStyle: const TextStyle(
              color: Color(0xFFCCCCCC),
              decoration: TextDecoration.lineThrough,
            ),
            outsideDaysVisible: false,
          ),
          onPageChanged: (focusedDay) {
            setState(() => _focusedDay = focusedDay);
          },
        ),
      ),
    );
  }

  Widget _buildAccommodationInfo(StayAccommodationDto item) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: item.firstImageUrl != null
                ? Image.network(item.firstImageUrl!, width: 64, height: 64, fit: BoxFit.cover,
                    errorBuilder: (context, err, _) => _imageFallback())
                : _imageFallback(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(item.address, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('월 ${_fmt(item.monthlyPrice)}원', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageFallback() => Container(
    width: 64, height: 64, color: AppColors.border,
    child: const Icon(Icons.home_outlined, color: AppColors.textHint),
  );

  Widget _buildSectionTitle(String title) => Text(
    title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
  );

  Widget _buildReadonlyField(String value, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(value, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
        ],
      ],
    );
  }

  Widget _buildPriceSummary(StayAccommodationDto item) {
    // 실제 입력된 팀원 수 + 대표자 1명 = 총 팀 인원
    final filledCount = _memberControllers.where((c) => c.text.trim().isNotEmpty).length;
    final teamCount = filledCount + 1; // +1: 대표자 본인 포함
    final teamPrice = PriceCalculator.calculateTeamPrice(
      monthlyPrice: item.monthlyPrice,
      months: _durationMonths,
      teams: teamCount,
      prices: item.prices,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Column(
        children: [
          _priceRow('원래 월세', '${_fmt(item.monthlyPrice)}원 / 월'),
          const SizedBox(height: 6),
          _priceRow('팀 인원', '$teamCount명 (대표자 포함, 입력 완료 기준)'),
          const SizedBox(height: 6),
          _priceRow('계약 기간', monthOptionLabel(_durationMonths)),
          Divider(height: 20, color: AppColors.primaryBorder),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('팀당 월세', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
              Text(
                teamPrice > 0 ? '${_fmt(teamPrice)}원 / 월' : '-',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
      ],
    );
  }

  String _fmt(int price) => price.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}
