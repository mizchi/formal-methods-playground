/// 二分探索の中点 (素直な版)。lo + hi があふれる
pub fn mid_naive(lo: u64, hi: u64) -> u64 {
    lo.wrapping_add(hi) / 2
}

/// 修正版
pub fn mid_safe(lo: u64, hi: u64) -> u64 {
    lo + (hi - lo) / 2
}
