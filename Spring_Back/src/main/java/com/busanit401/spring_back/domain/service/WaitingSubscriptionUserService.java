package com.busanit401.spring_back.domain.service;

import com.busanit401.spring_back.domain.SubscriptionsUser;
import com.busanit401.spring_back.domain.User;
import com.busanit401.spring_back.domain.WaitingSubscriptionUser;
import com.busanit401.spring_back.dto.waitingSubscriptionUser.WaitingSubscriptionReq;
import com.busanit401.spring_back.dto.waitingSubscriptionUser.WaitingSubscriptionResp;
import com.busanit401.spring_back.dto.waitingSubscriptionUser.WaitingSubscriptionSearchCondition;
import com.busanit401.spring_back.enums.MemberStatus;
import com.busanit401.spring_back.enums.NotificationType;
import com.busanit401.spring_back.enums.SubscriptionStatus;
import com.busanit401.spring_back.exception.BusinessException;
import com.busanit401.spring_back.exception.DuplicateException;
import com.busanit401.spring_back.exception.EntityNotFoundException;
import com.busanit401.spring_back.exception.ErrorCode;
import com.busanit401.spring_back.exception.InvalidStateException;
import com.busanit401.spring_back.domain.repository.SubscriptionsUserRepository;
import com.busanit401.spring_back.domain.repository.UserRepository;
import com.busanit401.spring_back.domain.repository.WaitingSubscriptionUserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.log4j.Log4j2;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@Service
@RequiredArgsConstructor
@Log4j2
@Transactional(readOnly = true)
public class WaitingSubscriptionUserService {

    private final WaitingSubscriptionUserRepository waitingRepository;
    private final SubscriptionsUserRepository subscriptionsUserRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;

    // ── 구독 신청 — 5단계 검증 후 저장 ─────────────────────────
    @Transactional
    public List<WaitingSubscriptionResp> apply(Long leaderId, WaitingSubscriptionReq req) {

        // 1단계: 대표자가 존재하고 탈퇴하지 않은 유저인지 확인
        User leader = findActiveUser(leaderId);

        // 2단계: 이미 이 숙소에 ACTIVE 구독이 있으면 중복 신청 차단
        validateDuplicateSubscription(leaderId, req.getAccommodationId());

        // 3단계: 같은 숙소의 PENDING/ACTIVE 구독과 날짜가 겹치는지 체크
        // endDate = startDate + durationMonths (개월 단위 계산)
        validateDateOverlap(req.getAccommodationId(), req.getStartDate(),
                req.getStartDate().plusMonths(req.getDurationMonths()));

        // 4단계: 팀원 조회 (username 또는 email 중 하나라도 맞으면 매칭)
        // 입력한 identifier 수와 조회 결과 수가 다르면 없는 팀원이 있는 것 → 예외
        List<User> members = findMembers(req.getMemberIdentifiers());
        validateMembersFound(req.getMemberIdentifiers(), members);

        // 5단계: SubscriptionsUser(구독 정보) 저장 → 대표자·개월수·시작일 기록
        SubscriptionsUser subscriptionsUser = SubscriptionsUser.create(leader, req);
        subscriptionsUserRepository.save(subscriptionsUser);

        // WaitingSubscriptionUser 저장 → 대표자(APPROVED) + 팀원들(PENDING) 각 1행씩
        List<WaitingSubscriptionUser> waitingList = buildWaitingList(subscriptionsUser, leader, members);
        waitingRepository.saveAll(waitingList);

        // 팀원 없이 대표만 신청한 경우: 전원이 이미 APPROVED → 즉시 관리자 알림 발송
        boolean allApproved = waitingList.stream()
                .allMatch(w -> w.getStatus() == MemberStatus.APPROVED);
        if (allApproved) {
            notificationService.notifyAdmin(
                    NotificationType.SUBSCRIPTION_READY,
                    "새로운 구독 신청이 승인 대기 중입니다. (구독 ID: " + subscriptionsUser.getId() + ")",
                    subscriptionsUser.getId()
            );
        }

        // 저장된 WaitingSubscriptionUser 목록을 DTO로 변환해 반환
        return waitingList.stream()
                .map(WaitingSubscriptionResp::from)
                .collect(Collectors.toList());
    }

    // ── 팀원 동의 처리 ────────────────────────────────────────
    @Transactional
    public WaitingSubscriptionResp approveMember(Long subscriptionsUserId, Long userId) {
        // 해당 팀원의 WaitingSubscriptionUser 조회
        WaitingSubscriptionUser waiting = findWaiting(subscriptionsUserId, userId);
        // 이미 동의/거절한 경우 예외 발생 (PENDING 상태만 처리 가능)
        validatePendingStatus(waiting);
        // 상태를 APPROVED로 변경 (엔티티 메서드 호출, DB 삭제 아님)
        waiting.approve();

        // 이 구독 건의 모든 팀원이 동의했는지 확인
        boolean allApproved = waitingRepository
                .findAllBySubscriptionsUserId(subscriptionsUserId)
                .stream()
                .allMatch(w -> w.getStatus() == MemberStatus.APPROVED);

        // 전원 동의 완료 → 관리자에게 최종 승인 요청 알림 발송
        if (allApproved) {
            notificationService.notifyAdmin(
                    NotificationType.SUBSCRIPTION_READY,
                    "새로운 구독 신청이 승인 대기 중입니다. (구독 ID: " + subscriptionsUserId + ")",
                    subscriptionsUserId
            );
            log.info("[전원 동의 완료] subscriptionsUserId: {}", subscriptionsUserId);
        }

        return WaitingSubscriptionResp.from(waiting);
    }

    // ── 팀원 거절 처리 ────────────────────────────────────────
    @Transactional
    public WaitingSubscriptionResp rejectMember(Long subscriptionsUserId, Long userId) {
        WaitingSubscriptionUser waiting = findWaiting(subscriptionsUserId, userId);
        // PENDING 상태인지 확인 (이미 처리된 요청 재처리 방지)
        validatePendingStatus(waiting);
        // 상태를 REJECTED로 변경
        waiting.reject();
        return WaitingSubscriptionResp.from(waiting);
    }

    // ── 내가 초대받은 구독 목록 조회 ─────────────────────────
    // PENDING 상태만 반환 → 아직 동의/거절하지 않은 초대만 표시
    public List<WaitingSubscriptionResp> getMyInvitations(Long userId) {
        return waitingRepository.findAllByUserIdAndStatus(userId, MemberStatus.PENDING)
                .stream()
                .map(WaitingSubscriptionResp::from)
                .collect(Collectors.toList());
    }

    // ── [관리자] 복합 조건 검색 ───────────────────────────────
    public List<WaitingSubscriptionResp> searchByCondition(WaitingSubscriptionSearchCondition condition) {
        return waitingRepository.searchByCondition(condition)
                .stream()
                .map(WaitingSubscriptionResp::from)
                .collect(Collectors.toList());
    }

    // ────────────────────────────────────────────────────────────
    // Private 헬퍼 메서드
    // ────────────────────────────────────────────────────────────

    // WaitingSubscriptionUser 목록 생성 — 대표자(APPROVED) + 팀원들(PENDING)
    private List<WaitingSubscriptionUser> buildWaitingList(
            SubscriptionsUser subscriptionsUser, User leader, List<User> members) {
        List<WaitingSubscriptionUser> waitingList = new java.util.ArrayList<>();
        // 대표자: 본인이 신청했으므로 즉시 APPROVED
        waitingList.add(WaitingSubscriptionUser.createLeader(subscriptionsUser, leader));
        // 팀원: 각자 동의해야 하므로 PENDING 상태로 저장
        members.stream()
                .map(member -> WaitingSubscriptionUser.createMember(subscriptionsUser, member))
                .forEach(waitingList::add);
        return waitingList;
    }

    // 팀원 identifier(username 또는 email)로 User 목록 조회
    // 두 필드를 OR 조건으로 동시에 검색 → 아이디로 입력해도, 이메일로 입력해도 찾음
    private List<User> findMembers(List<String> identifiers) {
        if (identifiers == null || identifiers.isEmpty()) return List.of();
        return userRepository.findAllByUsernameInOrEmailIn(identifiers);
    }

    // 입력한 identifier 수 vs 조회된 User 수 비교
    // 찾은 User의 username·email을 Set으로 만들어 입력값과 대조
    // 하나라도 못 찾으면 → MEMBER_NOT_FOUND 예외 (전체 신청 실패)
    private void validateMembersFound(List<String> identifiers, List<User> members) {
        if (identifiers == null || identifiers.isEmpty()) return;
        // 찾은 유저들의 username + email을 Set에 모아서 빠르게 포함 여부 확인
        Set<String> foundIdentifiers = members.stream()
                .flatMap(u -> Stream.of(u.getUsername(), u.getEmail()))
                .collect(Collectors.toSet());
        // 입력값 중 Set에 없는 것 = DB에 없는 유저
        List<String> notFound = identifiers.stream()
                .filter(id -> !foundIdentifiers.contains(id))
                .collect(Collectors.toList());
        if (!notFound.isEmpty()) {
            throw new EntityNotFoundException(ErrorCode.MEMBER_NOT_FOUND);
        }
    }

    // 같은 숙소에 이미 ACTIVE 구독이 있으면 중복 신청 차단
    private void validateDuplicateSubscription(Long userId, Long accommodationId) {
        if (subscriptionsUserRepository.existsByUserIdAndAccommodationIdAndStatus(
                userId, accommodationId, SubscriptionStatus.ACTIVE)) {
            throw new DuplicateException(ErrorCode.DUPLICATE_SUBSCRIPTION);
        }
    }

    // 신청 기간(newStart ~ newEnd)이 기존 PENDING/ACTIVE 구독 기간과 겹치는지 확인
    // → Repository 쿼리로 겹치는 구독이 1건이라도 있으면 예외 발생
    private void validateDateOverlap(Long accommodationId, LocalDate newStart, LocalDate newEnd) {
        List<SubscriptionStatus> checkStatuses = List.of(SubscriptionStatus.PENDING, SubscriptionStatus.ACTIVE);
        boolean hasOverlap = !subscriptionsUserRepository
                .findOverlappingSubscriptions(accommodationId, newStart, newEnd, checkStatuses)
                .isEmpty();
        if (hasOverlap) {
            throw new BusinessException(ErrorCode.SUBSCRIPTION_DATE_CONFLICT);
        }
    }

    // 동의/거절 처리 전 PENDING 상태인지 확인 (이미 처리된 요청 재처리 방지)
    private void validatePendingStatus(WaitingSubscriptionUser waiting) {
        if (waiting.getStatus() != MemberStatus.PENDING) {
            throw new InvalidStateException(ErrorCode.ALREADY_PROCESSED);
        }
    }

    // subscriptionsUserId + userId 조합으로 WaitingSubscriptionUser 1건 조회
    private WaitingSubscriptionUser findWaiting(Long subscriptionsUserId, Long userId) {
        return waitingRepository.findBySubscriptionsUserIdAndUserId(subscriptionsUserId, userId)
                .orElseThrow(() -> new EntityNotFoundException(ErrorCode.MEMBER_NOT_FOUND));
    }

    // userId로 유저 조회 + 탈퇴 여부 확인 (deletedAt 필드가 null 이 아니면 탈퇴 처리된 계정)
    private User findActiveUser(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new EntityNotFoundException(ErrorCode.MEMBER_NOT_FOUND));
        if (user.getDeletedAt() != null) {
            throw new InvalidStateException(ErrorCode.DELETED_USER);
        }
        return user;
    }
}

/*
 * ==================================================================================
 * [파일 정보]
 * 위치  : com.busanit401.spring_back.domain.service.WaitingSubscriptionUserService
 * 역할  : 구독 신청 비즈니스 로직 (5단계 검증 → 저장 → 알림)
 * 사용처 : WaitingSubscriptionUserController
 * ----------------------------------------------------------------------------------
 * [연관 파일]
 * - SubscriptionsUserRepository.java       : 구독 중복/날짜 겹침 조회
 * - WaitingSubscriptionUserRepository.java : WaitingSubscriptionUser 저장/조회
 * - UserRepository.java                    : 팀원 identifier 조회
 * - NotificationService.java              : 관리자 알림 발송
 * ----------------------------------------------------------------------------------
 * [apply() 5단계 검증 순서]
 * 1. findActiveUser       → 대표자 존재 + 탈퇴 여부
 * 2. validateDuplicate    → ACTIVE 구독 중복 체크
 * 3. validateDateOverlap  → PENDING/ACTIVE 날짜 겹침 체크
 * 4. findMembers + validateMembersFound → 팀원 존재 확인 (없으면 전체 실패)
 * 5. save SubscriptionsUser + WaitingSubscriptionUser
 * ----------------------------------------------------------------------------------
 * [DB 저장 구조]
 * SubscriptionsUser (1행) : 구독 건 정보 (대표자, 숙소, 기간)
 * WaitingSubscriptionUser  : 대표자(APPROVED) + 팀원 수 만큼 행 생성 (PENDING)
 * ==================================================================================
 */