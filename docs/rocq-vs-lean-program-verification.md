# Rocq と Lean を program verification で選ぶ基準

> Status: attributed reading note, 2026-08-05
>
> Source: Joomy Korkut, [Why Rocq is better than Lean for program verification](https://joomy.korkutblech.com/posts/2026-07-28-why-rocq-is-better.html), 2026-07-28

この記事を、Rocq と Lean の一般的な優劣ではなく、この repository のツール選択基準へ
反映するために整理する。記事は program verification に対象を限定した個人の経験談であり、
事実確認には Rocq / Lean の公式資料と各 project の一次資料を使う。

## 結論

この記事から採用する中心的な知見は次である。

> 証明対象が数学的な法則ではなく、実行、観測、抽出まで含む program semantics そのものなら、
> Rocq の artifact shape が Lean より自然な場合がある。

個人的なファーストチョイスである Alloy 6、Quint、Lean 4 は維持する。ただし、Rocq を
「既存 library が必要な場合だけの例外」とは捉えない。native codata、mechanized semantics、
extraction pipeline、program logic が成果物の中心なら、Rocq は積極的な first choice になり得る。

## Epistemic status

| 分類 | この文書での扱い |
| --- | --- |
| 公式に確認できる機構 | Rocq / Lean の reference manual を根拠にする |
| ecosystem の存在と活動 | project 公式site、repository、release情報を根拠にする |
| 可読性、移植コスト、使い勝手 | 記事著者の経験則として扱う |
| AI agent の得意不得意 | 記事にはbenchmarkがないため、選択基準にはしない |
| regulatory acceptance | 個別toolchainとprocessの先例であり、Rocq一般への保証とはみなさない |

## 主張ごとの整理

| 論点 | 記事の主張 | このrepoでの評価 |
| --- | --- | --- |
| native codata | Rocq は `Type` 上の `CoInductive` / `CoFixpoint` を直接持つ | 最も明確な技術差分 |
| nested inductive | Rocq は一部のnested relationを自然なproof objectのまま受理できる | 表現可能性よりproof engineering costの差 |
| extraction | Rocq は複数targetと複数TCBの経路を選べる | 強み。ただしproof boundaryを明記する |
| ecosystem | Iris、CompCert、VST、Interaction Treesなどの蓄積が厚い | 移植可能性ではなく既存資産と保守者を評価する |
| regulatory history | Rocq / CompCert には評価・qualificationの先例がある | project固有のevidenceとして扱う |
| AI agent | Leanの人気だけを理由に移行する必要はない | 同意するが、agent性能は実測して判断する |

## Native codata と cofixpoint

Lean の `coinductive` command は `Prop` 値の coinductive predicate を定義する。
Lean の公式資料は、Lean の type theory が coinductive type を直接持たず、この command が
predicate に限定されることを明記している。

Rocq は `CoInductive` で無限objectを型として宣言し、`CoFixpoint` で guarded corecursionを
定義できる。recursive callはconstructorの下に置く必要があり、unguardedな定義は拒否される。

この違いが load-bearing になる対象:

- infinite stream、game tree、interaction tree
- 非停止programを観測可能なtreeとして表すsemantics
- bisimulationやtrace equivalence
- 同じdefinitionをproofとextractionの両方で使うprogram
- mutualまたはindexedなcodata

Leanでもstreamを`Nat -> α`として表す、iteratorやstate machineを使う、libraryでcodataを
encodeする、といった方法はある。したがって「Leanでは表現不能」ではない。差は、Rocqでは
codata、productivity check、観測によるreasoning、lazy computationが同じ言語機構として
つながる点にある。

Leanの`Thunk`はruntimeではmemoizeされるが、そのcacheはlogicから不可視である。
`partial def`はtermination proofを要求しない代わりにlogic上opaqueになる。このため、
実行するrecursive producerと、unfoldして証明する対象を同じdefinitionにしたい場合、
Rocqのguarded `CoFixpoint`が適する可能性がある。

## Nested inductive は表現コストの問題

Leanはnested inductive typeをinternalにmutual inductiveへ変換して検査する。そのため、
nested occurrenceの引数にconstructor-local variableを含められないなど、公式に記載された
制限がある。

記事のJSON schema例では、field名の一致と再帰的validationを1つの`Forall2` derivationに
まとめたrelationをLeanが拒否する。Lean側でも次のように再構成できる。

- relationを複数の`Forall2`へ分ける
- mutual relationを定義する
- custom induction principleを作る
- indexや補助invariantを導入する

したがって比較すべきものはlogical expressivenessではなく、domainに自然なdefinitionを
保ったままproofを進められるか、そのためにどれだけ補助machineryを維持するかである。

## Extraction と proof boundary

Rocqの標準extractionはOCaml、Haskell、Schemeなどをtargetにできる。ecosystemには
verifiedまたは可読性を重視した別pipelineもある。ここで評価するのはtarget数だけではない。

- generated codeを人がreviewする必要があるか
- compiler、runtime、FFIのどこまでをTCBに含めるか
- extraction pipeline自体のcorrectness proofが必要か
- production codeとproof sourceのdriftをどう防ぐか
- axiomsやforeign constantsをどうrealizeするか

Rocqでsource theoremがcheckされたことは、生成binary全体の正しさを自動的に意味しない。
標準extractionにもaxiom realizationやtarget languageとの差に関する注意がある。記事中のgameも、
proof boundaryはRocq sourceまでで、生成C++、SDL、native runtimeは含まないと明記している。

採用時には次をledgerへ残す。

```text
proved source:
extraction backend and version:
generated artifact:
trusted compiler/runtime/FFI:
unverified boundary:
drift guard:
```

## Ecosystem と institutional history

記事が挙げる重要な資産には次がある。

- Interaction Trees / Choice Trees: effectful・非停止・nondeterministic programのsemantics
- Iris: stateful / concurrent program向けhigher-order separation logic
- Perennial / Aneris: crash-safe storageやdistributed program
- VST: CompCert semantics上のC verification
- CompCert、Vellvm、WasmCert: 実言語のsemanticsとverified compiler
- Fiat Crypto、Rupicola: correct-by-constructionなprogram synthesis

これらは理論上別proof assistantへ移植できても、既存proof、tactic、semantics、論文artifact、
CI、保守者まで含む蓄積は短期間では移らない。一方、記事自身も一部projectがinactiveであると
認めているため、採用前にversion compatibility、CI、release、保守責任を確認する。

ANSSIにはCommon Criteria評価でRocqを使うためのrequirementsがあり、CompCertには
aircraft向けqualificationの先例がある。ただし、このhistoryは特定version、toolchain、
evidence、運用process、対象systemに属する。Rocqで新規に書いたproofへ自動継承されない。

## このrepositoryでの選択ルール

### Leanを選ぶ

- 成果物が実装から独立した数学的法則
- type-level law、pure algorithm theorem、再利用するlemmaが中心
- native codataやalternate extraction backendを必要としない
- mathlibなどLean ecosystemが問題に合う

### Rocqを選ぶ

- executable semanticsそのものがproof artifact
- `CoInductive` / `CoFixpoint`とguarded productivityが本質
- compiler、interpreter、effect tree、bytecode semanticsを証明してextractする
- Iris、CompCert、VSTなどRocq固有のprogram-verification資産を使う
- certificationや既存verified pipelineの先例がtool選択に影響する

### 短い判断規則

```text
残したいartifactは「法則」か「証明されたprogram semantics」か?

法則
  -> Lean

program semanticsで、codata / extraction / program logicのどれかがload-bearing
  -> Rocq
```

config bug、finite relation、temporal traceの探索には、この分岐より前にZ3、Alloy、Quintを使う。

## Repository artifactへの含意

現在の[`StackCompiler.v`](../languages/rocq/StackCompiler.v)はmechanized semanticsの良い入口だが、
同じ定理はLeanでも自然に証明できる。これはRocqの基本probeであり、Leanとの差を決定づける
probeではない。

Rocq固有の価値を検査する次の候補はcoinductive protocolである。

```text
artifact:
  languages/rocq/CoinductiveProtocol.v

positive claim:
  guarded CoFixpointがinfinite event treeを生成する
  任意の観測prefixがprotocol invariantを保つ
  proof対象とextract対象が同じdefinitionである

negative control:
  constructorを経由しないrecursive callをguardedness checkerが拒否する

runtime check:
  OCamlへextractし、有限個のeventを観測する

boundary:
  extraction backend、OCaml compiler、runtime adapterは別途記録する
```

これにより、`StackCompiler.v`を共通のcompiler-correctness例、coinductive probeを
Rocq固有のprogram-verification例として分離できる。

## Decision ledger

| 項目 | 記録 |
| --- | --- |
| source | Joomy Korkutの記事。program verificationに限定した個人の経験則 |
| official observation | Leanのcoinductionはpredicate中心。Rocqはnative codataとguarded cofixpointを持つ |
| repository observation | 現在のstack compiler例はRocqでcheck済みだが、Leanとの差分probeではない |
| domain question | 長期的に残したいのはpure theoremか、実行・抽出するsemanticsか |
| decision | Alloy / Quint / Leanのdefaultは維持し、codata / extraction / program logicではRocqをfirst choiceにする |
| future lock | coinductive protocolの正例、unguarded負例、extraction boundaryを追加する |

## References

元記事:

- [Why Rocq is better than Lean for program verification](https://joomy.korkutblech.com/posts/2026-07-28-why-rocq-is-better.html)

公式資料:

- [Rocq: Coinductive types and corecursive functions](https://rocq-prover.org/doc/V9.1.1/refman/language/core/coinductive.html)
- [Rocq: Program extraction](https://rocq-prover.org/doc/V9.1.1/refman/addendum/extraction.html)
- [Lean: Coinductive predicates and partial functions](https://lean-lang.org/doc/reference/latest/Definitions/Recursive-Definitions/)
- [Lean: Lazy computations](https://lean-lang.org/doc/reference/latest/Basic-Types/Lazy-Computations/)
- [Lean: Inductive types](https://lean-lang.org/doc/reference/latest/The-Type-System/Inductive-Types/)
- [Lean: Elaboration and compilation](https://lean-lang.org/doc/reference/latest/Elaboration-and-Compilation/)

ecosystem / institutional primary sources:

- [Iris Project](https://iris-project.org/)
- [CompCert](https://compcert.org/)
- [ANSSI: Requirements on the use of Rocq in Common Criteria evaluations](https://cyber.gouv.fr/sites/default/files/document/anssi-requirements-on-the-use-of-rocq-in-the-context-of-common-criteria-evaluations-v1.2-en.pdf)
