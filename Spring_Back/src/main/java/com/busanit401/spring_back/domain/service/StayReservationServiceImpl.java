package com.busanit401.spring_back.domain.service;

import com.busanit401.spring_back.domain.User;
import com.busanit401.spring_back.domain.entity.StayAccommodation;
import com.busanit401.spring_back.domain.entity.StayReservation;
import com.busanit401.spring_back.domain.repository.StayAccommodationRepository;
import com.busanit401.spring_back.domain.repository.StayReservationRepository;
import com.busanit401.spring_back.domain.repository.UserRepository;
import com.busanit401.spring_back.dto.StayReservationRequestDto;
import com.busanit401.spring_back.dto.StayReservationResponseDto;
import com.busanit401.spring_back.exception.BusinessException;
import com.busanit401.spring_back.exception.ErrorCode;
import com.busanit401.spring_back.enums.StayReservationStatus;
import lombok.RequiredArgsConstructor;
import lombok.extern.log4j.Log4j2;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;

@Log4j2
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class StayReservationServiceImpl implements StayReservationService {

    private final StayReservationRepository reservationRepository;
    private final StayAccommodationRepository accommodationRepository;
    private final UserRepository userRepository;

    // ── 내 예약 목록 조회 ─────────────────────────────────────
    // 정렬 그룹: 1=다가오는 예약(시작일↑) → 2=취소됨(최근순) → 3=지난 예약(종료일↓)
    @Override
    public List<StayReservationResponseDto> getReservations(Long userId) {
        log.info("✅ [StayReservationService] 내 예약 목록 조회 → userId: {}", userId);
        LocalDate today = LocalDate.now();

        // 그룹 번호: 1=다가오는 예약, 2=취소됨, 3=지난 예약
        Comparator<StayReservationResponseDto> sortOrder = (a, b) -> {
            int ga = (a.getStatus() == StayReservationStatus.CANCELLED) ? 2
                    : a.getEndDate().isBefore(today) ? 3 : 1;
            int gb = (b.getStatus() == StayReservationStatus.CANCELLED) ? 2
                    : b.getEndDate().isBefore(today) ? 3 : 1;
            if (ga != gb) return Integer.compare(ga, gb);
            // 오름차순(과거위) : a.compareTo(b), 내림차순(최신위) : b.compareTo(a)
            if (ga == 1) return a.getStartDate().compareTo(b.getStartDate()); // 다가오는: 시작일 오름차순
            if (ga == 2) return b.getStartDate().compareTo(a.getStartDate()); // 취소: 최근순
            return b.getEndDate().compareTo(a.getEndDate());                  // 지난: 종료일 내림차순
        };

        List<StayReservationResponseDto> result = reservationRepository.findByUserId(userId).stream()
                .map(StayReservationResponseDto::from)
                .sorted(sortOrder)
                .collect(Collectors.toList());
        log.info("✅ [StayReservationService] 내 예약 목록 조회 완료 → 총 {}건", result.size());
        return result;
    }

    // ── 예약 생성 ─────────────────────────────────────────────
    // 처리 순서:
    //   1. 숙소/유저 존재 여부 확인
    //   2. CONFIRMED 예약과 날짜 중복 체크
    //   3. 예약 저장 (상태: CONFIRMED)
    @Override
    @Transactional
    public StayReservationResponseDto createReservation(Long userId, StayReservationRequestDto requestDto) {
        log.info("✅ [StayReservationService] 예약 생성 시작 → userId: {}, accommodationId: {}", userId, requestDto.getAccommodationId());

        // ── 1단계: 숙소/유저 조회 ────────────────────────────
        StayAccommodation accommodation = accommodationRepository.findById(requestDto.getAccommodationId())
                .orElseThrow(() -> new BusinessException(ErrorCode.STAY_ACCOMMODATION_NOT_FOUND, " id: " + requestDto.getAccommodationId()));

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.STAY_USER_NOT_FOUND, " id: " + userId));

        // ── 2단계: 날짜 중복 체크 (CONFIRMED 상태만) ─────────
        // 겹침 조건: 신청 end >= 기존 start AND 신청 start <= 기존 end
        List<StayReservation> confirmed = reservationRepository
                .findByStayAccommodationIdAndStatus(requestDto.getAccommodationId(), StayReservationStatus.CONFIRMED);

        boolean isDuplicate = confirmed.stream().anyMatch(r ->
                !requestDto.getEndDate().isBefore(r.getStartDate()) &&
                        !requestDto.getStartDate().isAfter(r.getEndDate())
        );

        if (isDuplicate) {
            log.info("❌ [StayReservationService] 예약 생성 실패 → 날짜 중복");
            throw new BusinessException(ErrorCode.STAY_RESERVATION_DUPLICATE);
        }

        // ── 3단계: 예약 저장 ──────────────────────────────────
        StayReservation reservation = StayReservation.builder()
                .stayAccommodation(accommodation)
                .user(user)
                .startDate(requestDto.getStartDate())
                .endDate(requestDto.getEndDate())
                .status(StayReservationStatus.CONFIRMED)
                .build();

        StayReservationResponseDto result = StayReservationResponseDto.from(reservationRepository.save(reservation));
        log.info("✅ [StayReservationService] 예약 생성 완료 → reservationId: {}", result.getId());
        return result;
    }

    // ── 숙소별 확정 예약 목록 조회 (달력 비활성 날짜용) ──────
    // CONFIRMED 상태 예약만 반환 → 프론트 달력에서 비활성 날짜 표시에 사용
    @Override
    public List<StayReservationResponseDto> getReservationsByAccommodation(Long accommodationId) {
        log.info("✅ [StayReservationService] 숙소별 확정 예약 조회 → accommodationId: {}", accommodationId);
        return reservationRepository
                .findByStayAccommodationIdAndStatus(accommodationId, StayReservationStatus.CONFIRMED)
                .stream()
                .map(StayReservationResponseDto::from)
                .collect(Collectors.toList());
    }

    // ── [관리자] 전체 예약 목록 조회 ──────────────────────────
    // userId 없으면 전체, 있으면 해당 유저 예약만 / 시작일 내림차순
    @Override
    public List<StayReservationResponseDto> getAllReservations(Long userId) {
        log.info("✅ [StayReservationService] 전체 예약 목록 조회 (관리자) → userId: {}", userId);
        List<StayReservationResponseDto> result = (userId != null
                ? reservationRepository.findByUserId(userId)
                : reservationRepository.findAll())
                .stream()
                .map(StayReservationResponseDto::from)
                .sorted(Comparator.comparing(StayReservationResponseDto::getStartDate).reversed())
                .collect(Collectors.toList());
        log.info("✅ [StayReservationService] 전체 예약 목록 조회 완료 → 총 {}건", result.size());
        return result;
    }

    // ── 예약 취소 ─────────────────────────────────────────────
    // 본인 예약인지 확인 후 CANCELLED 상태로 변경 (삭제 아님)
    @Override
    @Transactional
    public void cancelReservation(Long reservationId, Long userId) {
        log.info("✅ [StayReservationService] 예약 취소 시작 → reservationId: {}, userId: {}", reservationId, userId);

        StayReservation reservation = reservationRepository.findById(reservationId)
                .orElseThrow(() -> new BusinessException(ErrorCode.STAY_RESERVATION_NOT_FOUND, " id: " + reservationId));

        // 본인 예약인지 확인
        if (!reservation.getUser().getId().equals(userId)) {
            log.info("❌ [StayReservationService] 예약 취소 실패 → 본인 예약 아님");
            throw new BusinessException(ErrorCode.STAY_RESERVATION_UNAUTHORIZED);
        }

        reservation.cancel();
        log.info("✅ [StayReservationService] 예약 취소 완료 → reservationId: {}", reservationId);
    }
}

/*
 * ==================================================================================
 * [파일 정보]
 * 위치  : com.busanit401.spring_back.domain.service.StayReservationServiceImpl
 * 역할  : 숙소 예약 비즈니스 로직 (조회/생성/취소)
 * 사용처 : StayReservationController
 * ----------------------------------------------------------------------------------
 * [연관 파일]
 * - StayReservationRepository.java     : 예약 DB 조회/저장
 * - StayAccommodationRepository.java   : 숙소 조회
 * - UserRepository.java                : 유저 조회
 * - StayReservationResponseDto.java    : 반환 DTO (from() 정적 메서드)
 * - StayReservationRequestDto.java     : 입력 DTO
 * - StayReservation.java               : 예약 엔티티 (cancel() 메서드)
 * - StayReservationService.java        : 인터페이스
 * - ErrorCode.java                     : 예외 코드 (STAY_* 코드)
 * ----------------------------------------------------------------------------------
 * [변경 이력]
 * - 최초 작성 : 예약 생성/취소 기본 구조, RuntimeException 사용
 * - 변경       : RuntimeException → BusinessException 으로 교체 (ErrorCode 연동)
 *               getReservationsByAccommodation() 추가 (달력 비활성 날짜용)
 *               getReservations() 정렬 로직 추가
 *               → 다가오는 예약(1) → 취소됨(2) → 지난 예약(3) 그룹 정렬
 * ----------------------------------------------------------------------------------
 * [메서드 목록]
 * - getReservations(userId)                         : 내 예약 목록 조회 (정렬 적용)
 * - createReservation(userId, requestDto)           : 예약 생성 (중복체크 → 저장)
 * - getReservationsByAccommodation(accommodationId) : 숙소별 확정 예약 목록 조회
 * - cancelReservation(reservationId, userId)        : 예약 취소 (본인 확인 → CANCELLED)
 * - getAllReservations(userId)                      : [관리자] 전체 예약 목록 조회 (userId 없으면 전체, 있으면 필터링 / 시작일 내림차순)
 * ----------------------------------------------------------------------------------
 * [파일 흐름과 순서]
 * [조회] GET  → getReservations(userId)
 *             → findByUserId() → DTO 변환 → 그룹 정렬 후 반환
 *
 * [생성] POST → createReservation(userId, requestDto)
 *             → 숙소/유저 조회 → CONFIRMED 날짜 중복 체크 → 예약 저장
 *
 * [달력] GET  → getReservationsByAccommodation(accommodationId)
 *             → CONFIRMED 예약만 조회 → DTO 변환 후 반환
 *
 * [취소] PATCH → cancelReservation(reservationId, userId)
 *              → 예약 조회 → 본인 확인 → reservation.cancel() (CANCELLED 변경)
 *
 * [관리자] GET → getAllReservations()
 *              → findAll() → DTO 변환 → 시작일 내림차순 정렬 후 반환
 * ----------------------------------------------------------------------------------
 * [주의사항 / 참고]
 * - cancel() 은 StayReservation 엔티티 메서드 → status 를 CANCELLED 로 변경 (DB 삭제 아님)
 * - 날짜 중복 체크: CANCELLED 예약 제외, CONFIRMED 만 체크
 * ⚠️ [TODO] 로그인 완전 연동 후 Controller 의 @RequestParam userId 제거 예정
 * ==================================================================================
 */
