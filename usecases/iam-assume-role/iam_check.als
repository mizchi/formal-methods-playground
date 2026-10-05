-- 手で書く性質。事実は iam_facts.als (生成) から読む
open iam_facts

-- 入口のロールから、AssumeRole をどう連鎖しても、管理者権限に届かない
assert NoEscalation {
  no Entry.*canAssume & Privileged
}
check NoEscalation for 5

-- 空振りでないことの確認: 入口のロールから、別のロールにはちゃんと届く
run EntryReachesOtherRoles {
  some Entry.^canAssume - Entry
} for 5
