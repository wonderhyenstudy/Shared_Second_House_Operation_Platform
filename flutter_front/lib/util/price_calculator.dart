import 'package:flutter_front/domain/dto/stay_accommodation_dto.dart';

class PriceCalculator {
  // 1. 팀당 월세 계산 (할인율 + 팀 분할)
  // 공유문서 공식: (월세 × (1 - 할인율) / 팀수).floor()
  static int calculateTeamPrice({
    required int monthlyPrice, // 기본월세
    required int months,  // 계약개월
    required int teams, // 팀수
    required List<StayAccommodationPriceDto> prices, // 할인율 구간 목록
    // minMonths: 1   maxMonths: 3    discountRate: 0.0   → 1~2개월: 할인 없음
    // minMonths: 3   maxMonths: 6    discountRate: 0.05  → 3~5개월: 5% 할인
    // minMonths: 6   maxMonths: null discountRate: 0.10  → 6개월 이상: 10% 할인
  }) {
    if (prices.isEmpty || teams <= 0) return monthlyPrice;

    try {
      // 조건에 맞는 구간 찾기 priceInfo
      final priceInfo = prices.firstWhere(
        // 계약 개월 수가 해당 구간의 최소 개월수 이상
        // 최대 개월수가 null이거나,
        // 최대 개월수가 있다면 계약 개월수가 최대 개월수 보다 작아야 한다
        // 조건이 맞으면 통과
        (p) => months >= p.minMonths && (p.maxMonths == null || months < p.maxMonths!),
        // A 구간: minMonths: 1, maxMonths: 3 (1개월 이상 ~ 3개월 미만)
        // B 구간: minMonths: 3, maxMonths: 6 (3개월 이상 ~ 6개월 미만)
        // C 구간: minMonths: 6, maxMonths: null (6개월 이상~ 쭉)
      );
      // 기본 가격을 위에 구간에 맞게 할인율 적용
      // .floor() : 소수점 이하 금액을 버림(절사)
      return (monthlyPrice * (1 - priceInfo.discountRate) / teams).floor(); // 금액계산
    } catch (_) {
      // 구간 미매칭 → 할인 없이 팀 분할만
      return (monthlyPrice / teams).floor();
    }
  }
  // 2. 총 비용 = 팀당 월세 × 개월수
  static int calculateTotalPrice({
    required int monthlyPrice,
    required int months,
    required int teams,
    required List<StayAccommodationPriceDto> prices,
  }) {
    return calculateTeamPrice(
          monthlyPrice: monthlyPrice,
          months: months,
          teams: teams,
          prices: prices,
        ) *
        months;
  }

  // 3. 해당 개월수의 할인율 반환 (없으면 0.0)
  static double getDiscountRate({
    required int months,
    required List<StayAccommodationPriceDto> prices,
  }) {
    try {
      final priceInfo = prices.firstWhere(
        (p) => months >= p.minMonths && (p.maxMonths == null || months < p.maxMonths!),
      );
      return priceInfo.discountRate;
    } catch (_) {
      return 0.0;
    }
  }
}
