import Std.Tactic.BVDecide

-- Lean の章で証明した中点の計算
def midSafe (lo hi : BitVec 64) : BitVec 64 := lo + (hi - lo) / 2

def midSpec (lo hi : BitVec 64) : BitVec 64 :=
  ((lo.zeroExtend 65 + hi.zeroExtend 65) / 2).truncate 64

theorem midSafe_correct (lo hi : BitVec 64) (h : lo ≤ hi) :
    midSafe lo hi = midSpec lo hi := by
  simp only [midSafe, midSpec]
  bv_decide

-- オラクルとして動かす: 標準入力の "lo hi" に、中点を 1 行ずつ返す
partial def loop (stdin : IO.FS.Stream) (stdout : IO.FS.Stream) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  match line.trimAscii.toString.splitOn " " with
  | [a, b] =>
    let lo := (a.toNat!).toUInt64.toBitVec
    let hi := (b.toNat!).toUInt64.toBitVec
    stdout.putStrLn (toString (midSafe lo hi).toNat)
    stdout.flush
  | _ => stdout.putStrLn "error"
  loop stdin stdout

def main : IO Unit := do
  loop (← IO.getStdin) (← IO.getStdout)
