//! Lean で証明した中点を、C 経由でビルドした実行ファイルをオラクルにして、
//! Rust の実装と突き合わせる。LEAN_ORACLE にオラクルのパスを渡す。
use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};

fn oracle(pairs: &[(u64, u64)]) -> Vec<u64> {
    let path = std::env::var("LEAN_ORACLE").expect("LEAN_ORACLE にオラクルのパスを設定する");
    let mut child = Command::new(path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("オラクルを起動できない");
    let mut stdin = child.stdin.take().unwrap();
    let input: String = pairs.iter().map(|(lo, hi)| format!("{lo} {hi}\n")).collect();
    let writer = std::thread::spawn(move || stdin.write_all(input.as_bytes()).unwrap());
    let out: Vec<u64> = BufReader::new(child.stdout.take().unwrap())
        .lines()
        .map(|l| l.unwrap().parse().unwrap())
        .collect();
    writer.join().unwrap();
    child.wait().unwrap();
    out
}

// 境界の値と、種を固定した乱数で、lo <= hi の組を作る
fn cases() -> Vec<(u64, u64)> {
    let mut v = vec![(0, 0), (0, u64::MAX), (u64::MAX, u64::MAX), (u64::MAX - 1, u64::MAX)];
    let mut x: u64 = 88172645463325252;
    for _ in 0..10_000 {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        let a = x;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        let b = x;
        v.push((a.min(b), a.max(b)));
    }
    v
}

fn first_mismatch(f: fn(u64, u64) -> u64) -> Option<(u64, u64, u64, u64)> {
    let cs = cases();
    let expected = oracle(&cs);
    cs.iter()
        .zip(expected)
        .map(|(&(lo, hi), e)| (lo, hi, f(lo, hi), e))
        .find(|&(_, _, got, e)| got != e)
}

#[test]
fn naive_disagrees_with_lean() {
    let m = first_mismatch(midpoint::mid_naive);
    println!("食い違い (lo, hi, Rust, Lean): {m:?}");
    assert!(m.is_some());
}

#[test]
fn safe_agrees_with_lean() {
    assert_eq!(first_mismatch(midpoint::mid_safe), None);
}
