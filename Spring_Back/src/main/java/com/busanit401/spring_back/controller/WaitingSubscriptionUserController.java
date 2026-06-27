package com.busanit401.spring_back.controller;

import com.busanit401.spring_back.dto.waitingSubscriptionUser.WaitingSubscriptionReq;
import com.busanit401.spring_back.dto.waitingSubscriptionUser.WaitingSubscriptionResp;
import com.busanit401.spring_back.dto.waitingSubscriptionUser.WaitingSubscriptionSearchCondition;
import com.busanit401.spring_back.domain.service.WaitingSubscriptionUserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.List;

@RestController
@RequestMapping("/api/waiting")
@RequiredArgsConstructor
public class WaitingSubscriptionUserController {

    private final WaitingSubscriptionUserService waitingService;

    // ── 구독 신청 (대표자 호출) ───────────────────────────────
    // leaderId: URL 경로로 받는 대표자 userId
    // WaitingSubscriptionReq: 팀원 identifier 목록 + 개월수 + 시작일
    // 201 Created 반환 → 생성된 WaitingSubscriptionUser 목록(대표+팀원 각 1행)
    @PostMapping("/apply/{leaderId}")
    public ResponseEntity<List<WaitingSubscriptionResp>> apply(
            @PathVariable Long leaderId,
            @RequestBody @Valid WaitingSubscriptionReq req) {
        return ResponseEntity.status(201).body(waitingService.apply(leaderId, req));
    }

    // ── 팀원 구독 동의 ────────────────────────────────────────
    // subscriptionsUserId: 어느 구독 건인지 (SubscriptionsUser PK)
    // userId: 동의하는 팀원 userId
    // 팀원 전원이 동의하면 Service에서 관리자에게 알림 발송
    @PostMapping("/{subscriptionsUserId}/approve/{userId}")
    public ResponseEntity<WaitingSubscriptionResp> approve(
            @PathVariable Long subscriptionsUserId,
            @PathVariable Long userId) {
        return ResponseEntity.ok(waitingService.approveMember(subscriptionsUserId, userId));
    }

    // ── 팀원 구독 거절 ────────────────────────────────────────
    // 거절한 팀원의 WaitingSubscriptionUser 상태 → REJECTED
    @PostMapping("/{subscriptionsUserId}/reject/{userId}")
    public ResponseEntity<WaitingSubscriptionResp> reject(
            @PathVariable Long subscriptionsUserId,
            @PathVariable Long userId) {
        return ResponseEntity.ok(waitingService.rejectMember(subscriptionsUserId, userId));
    }

    // ── 내가 초대받은 구독 목록 조회 ─────────────────────────
    // PENDING 상태인 것만 반환 → 아직 동의/거절하지 않은 초대 목록
    @GetMapping("/my/{userId}")
    public ResponseEntity<List<WaitingSubscriptionResp>> getMyInvitations(
            @PathVariable Long userId) {
        return ResponseEntity.ok(waitingService.getMyInvitations(userId));
    }

    // ── [관리자] 복합 조건 검색 ───────────────────────────────
    // WaitingSubscriptionSearchCondition: 상태·숙소ID·날짜 등 필터 조건 DTO
    @GetMapping("/admin/search")
    public ResponseEntity<List<WaitingSubscriptionResp>> searchByCondition(
            WaitingSubscriptionSearchCondition condition) {
        return ResponseEntity.ok(waitingService.searchByCondition(condition));
    }
}

/*
 * ==================================================================================
 * [파일 정보]
 * 위치  : com.busanit401.spring_back.controller.WaitingSubscriptionUserController
 * 역할  : 구독 신청 REST API 엔드포인트 (요청 수신 → Service 호출 → 응답 반환)
 * 사용처 : Flutter 앱 (stay_subscription_apply_screen.dart)
 * ----------------------------------------------------------------------------------
 * [연관 파일]
 * - WaitingSubscriptionUserService.java    : 비즈니스 로직 (5단계 검증 → 저장)
 * - WaitingSubscriptionReq.java           : 구독 신청 요청 DTO
 * - WaitingSubscriptionResp.java          : 응답 DTO
 * - WaitingSubscriptionSearchCondition.java : 관리자 검색 조건 DTO
 * ----------------------------------------------------------------------------------
 * [API 목록]
 * - POST  /api/waiting/apply/{leaderId}              : 구독 신청
 * - POST  /api/waiting/{subId}/approve/{userId}      : 팀원 동의
 * - POST  /api/waiting/{subId}/reject/{userId}       : 팀원 거절
 * - GET   /api/waiting/my/{userId}                   : 내 초대 목록(PENDING)
 * - GET   /api/waiting/admin/search                  : [관리자] 복합 조건 검색
 * ----------------------------------------------------------------------------------
 * [흐름 요약]
 * 대표자 신청 → apply() → 5단계 검증 → SubscriptionsUser + WaitingSubscriptionUser 저장
 * 팀원 동의   → approveMember() → 전원 동의 시 관리자 알림 발송
 * 팀원 거절   → rejectMember()
 * ==================================================================================
 */