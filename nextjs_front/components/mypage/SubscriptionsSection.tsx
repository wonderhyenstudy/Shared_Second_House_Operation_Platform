/*
 * ==================================================================================
 * [파일 정보]
 * 위치  : components/mypage/SubscriptionsSection.tsx
 * 역할  : 내 구독 목록 컴포넌트 (마이페이지 탭 중 하나)
 * 사용처 : app/mypage/page.tsx → activeMenu === 'subscriptions' 일 때 렌더링
 * ----------------------------------------------------------------------------------
 * [연관 파일]
 * - lib/api.ts                              : fetch 클라이언트 (Bearer 토큰 자동 첨부)
 * - Spring: SubscriptionsController.java    : GET /subscriptions/my/{userId}
 * - Spring: StayAccommodationController.java: GET /api/stay/accommodations/{id}
 * - Spring: GuestChatController.java        : GET /api/guest/chat/room/{accommodationId}
 * ----------------------------------------------------------------------------------
 * [기능 목록]
 * - userId 획득 → 내 구독 목록 조회 (순차) → 숙소 정보 병렬 조회
 * - 상태 배지: 구독 중(ACTIVE) / 승인 대기(PENDING) / 만료됨(EXPIRED) / 취소됨(CANCELLED)
 * - ACTIVE 구독만 채팅 + 예약하기 버튼 표시
 * ==================================================================================
 */

"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { api } from "@/lib/api";
import { UserResp } from "@/types/auth";
import {
  SubscriptionsUserResp,
  SubscriptionStatus,
} from "@/types/subscription";

interface AccommodationInfo {
  name: string;
  address: string;
}

// SubscriptionsUserResp에 숙소 이름·주소를 추가 확장한 로컬 타입
interface SubscriptionRow extends SubscriptionsUserResp {
  accommodationName?: string;
  accommodationAddress?: string;
}

export default function SubscriptionsSection() {
  const router = useRouter();
  const [rows, setRows] = useState<SubscriptionRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // 1단계: 로그인 유저 정보 조회 (JWT에서 userId 추출)
    api
      .get<UserResp>("/api/users")
      // 2단계: userId로 내 구독 목록 조회 (userId를 먼저 알아야 하므로 순차 처리)
      .then((userData) =>
        api.get<SubscriptionsUserResp[]>(
          `/api/subscriptions/my/${userData.userId}`,
        ),
      )
      .then((subs) => {
        const list = Array.isArray(subs) ? subs : [];
        // 3단계: 각 구독의 숙소 이름·주소를 Promise.all로 병렬 조회
        // 숙소 정보 API는 인증 없이 호출 가능 (permitAll)
        return Promise.all(
          list.map((s) =>
            api
              .get<AccommodationInfo>(
                `/api/stay/accommodations/${s.accommodationId}`,
              )
              .then((acc) => ({
                ...s,                              // 기존 구독 데이터 유지
                accommodationName: acc.name,
                accommodationAddress: acc.address,
              }))
              // 숙소 정보 조회 실패 시 이름·주소 없이 구독 카드는 표시 (전체 실패 방지)
              .catch(() => ({ ...s })),
          ),
        );
      })
      .then(setRows)
      .catch((err) => console.log("구독 목록 조회 실패:", err))
      .finally(() => setLoading(false));
  }, []);

  // 채팅 버튼 클릭 — 숙소 ID로 채팅방 ID를 조회한 뒤 채팅 페이지로 이동
  const handleChatButtonClick = async (accommodationId: number) => {
    try {
      // 백엔드에 숙소 ID를 보내 해당 숙소 채팅방 정보(id)를 받아옴
      const chatRoom = await api.get<{ id: number }>(
        `/api/guest/chat/room/${accommodationId}`,
      );

      if (chatRoom && chatRoom.id) {
        // 채팅 페이지에서 ?roomId=방번호 쿼리스트링으로 방을 식별함
        router.push(`/guestChat?roomId=${chatRoom.id}`);
      } else {
        alert("채팅방 정보를 불러올 수 없습니다.");
      }
    } catch (error) {
      console.error("채팅방 이동 실패:", error);
      alert("채팅방 연결 중 오류가 발생했습니다.");
    }
  };

  // 구독 상태 → 한국어 레이블 + 배지 색상 매핑
  // ACTIVE: 관리자 승인 완료 / PENDING: 팀원 동의 or 관리자 승인 대기
  // EXPIRED: 구독 기간 만료 / CANCELLED: 취소됨
  const getStatusBadge = (status: SubscriptionStatus) => {
    switch (status) {
      case "ACTIVE":
        return { label: "구독 중", cls: "bg-[#EAF3DE] text-[#3B6D11]" };
      case "PENDING":
        return { label: "승인 대기", cls: "bg-[#FFF8E6] text-[#B07D1A]" };
      case "EXPIRED":
        return { label: "만료됨", cls: "bg-[#F0EBE5] text-[#8C8178]" };
      case "CANCELLED":
        return { label: "취소됨", cls: "bg-[#F0EBE5] text-[#8C8178]" };
    }
  };

  if (loading) {
    return (
      <div className="bg-white border border-[#E4DDD3] rounded-xl overflow-hidden">
        <div className="bg-[#3B6D11] px-5 py-3.5 flex items-center gap-2 text-white text-sm font-medium">
          <HomeIcon />내 구독 목록
        </div>
        <div className="flex items-center justify-center py-16">
          <div className="w-6 h-6 border-2 border-[#3B6D11] border-t-transparent rounded-full animate-spin" />
        </div>
      </div>
    );
  }

  return (
    <div className="bg-white border border-[#E4DDD3] rounded-xl overflow-hidden">
      {/* 헤더 */}
      <div className="bg-[#3B6D11] px-5 py-3.5 flex items-center justify-between">
        <div className="flex items-center gap-2 text-white text-sm font-medium">
          <HomeIcon />내 구독 목록
        </div>
        <span className="text-xs text-white/60">{rows.length}건</span>
      </div>

      {/* 목록 */}
      {rows.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-[#8C8178]">
          <svg
            width="36"
            height="36"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.4"
            className="mb-3 opacity-40"
            aria-hidden="true"
          >
            <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
            <polyline points="9 22 9 12 15 12 15 22" />
          </svg>
          <p className="text-sm">구독 내역이 없어요.</p>
        </div>
      ) : (
        rows.map((r, i) => {
          const { label, cls } = getStatusBadge(r.status);

          return (
            <div
              key={r.subscriptionId}
              className={`px-5 py-4 ${i < rows.length - 1 ? "border-b border-[#F0EBE5]" : ""}`}
            >
              {/* 숙소명 + 상태 */}
              <div className="flex items-center justify-between mb-1">
                <Link
                  href={`/accommodations/${r.accommodationId}`}
                  className="text-sm font-medium text-[#2A2520] hover:text-[#3B6D11] transition-colors"
                >
                  {r.accommodationName ?? `숙소 #${r.accommodationId}`}
                </Link>
                <span
                  className={`text-xs px-2 py-0.5 rounded-full font-medium ${cls}`}
                >
                  {label}
                </span>
              </div>

              {/* 주소 */}
              {r.accommodationAddress && (
                <p className="text-xs text-[#8C8178] mb-3">
                  {r.accommodationAddress}
                </p>
              )}

              {/* 구독 기간 */}
              <div className="flex items-center gap-2 text-xs text-[#171717] bg-[#F7F4EF] rounded-lg px-3 py-2 w-fit mb-3">
                <svg
                  width="13"
                  height="13"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.8"
                  aria-hidden="true"
                >
                  <rect x="3" y="4" width="18" height="18" rx="2" ry="2" />
                  <line x1="16" y1="2" x2="16" y2="6" />
                  <line x1="8" y1="2" x2="8" y2="6" />
                  <line x1="3" y1="10" x2="21" y2="10" />
                </svg>
                <span>{r.startDate}</span>
                <span className="text-[#B5ADA4]">→</span>
                <span>{r.endDate}</span>
                <span className="text-[#171717]">({r.durationMonths}개월)</span>
              </div>

              {/* 채팅 + 예약하기 버튼 — ACTIVE(구독 중) 상태만 표시
                  PENDING/EXPIRED/CANCELLED는 서비스 이용 불가이므로 버튼 없음 */}
              {r.status === "ACTIVE" && (
                <div className="flex gap-2">
                  <button
                    onClick={() => handleChatButtonClick(r.accommodationId)}
                    className="flex-1 h-10 flex items-center justify-center gap-1.5 text-sm font-medium text-[#3B6D11] border border-[#D6E4C8] bg-[#F2F7EC] rounded-lg hover:bg-[#EAF3DE] transition-colors cursor-pointer"
                  >
                    <svg
                      width="14"
                      height="14"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="1.8"
                      aria-hidden="true"
                    >
                      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                    </svg>
                    채팅
                  </button>
                  <Link
                    href={`/reservations/${r.accommodationId}`}
                    className="flex-1 flex items-center justify-center gap-1.5 h-10 text-sm !text-red-500 border border-red-200 bg-red-50 rounded-lg hover:bg-red-100 transition-colors"
                  >
                    <svg
                      width="14"
                      height="14"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="1.8"
                      aria-hidden="true"
                    >
                      <rect x="3" y="4" width="18" height="18" rx="2" ry="2" />
                      <line x1="16" y1="2" x2="16" y2="6" />
                      <line x1="8" y1="2" x2="8" y2="6" />
                      <line x1="3" y1="10" x2="21" y2="10" />
                    </svg>
                    예약하기
                  </Link>
                </div>
              )}
            </div>
          );
        })
      )}
    </div>
  );
}

function HomeIcon() {
  return (
    <svg
      width="17"
      height="17"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      aria-hidden="true"
    >
      <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
      <polyline points="9 22 9 12 15 12 15 22" />
    </svg>
  );
}
