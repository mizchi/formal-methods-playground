# P

P は、typed event と state machine で actor / protocol を書き、
runtime schedule を探索する言語である。

TLA+ より実装に近く、message handler が主語になる。

## 最小チュートリアル

登場人物は `machine` と `event`。

```p
event ePing: machine;
event ePong;

machine Sender {
  start state Init {
    entry (receiver: machine) {
      send receiver, ePing, this;
    }

    on ePong goto Done;
  }

  state Done {}
}
```

受信側:

```p
machine Receiver {
  start state Listening {
    on ePing do (sender: machine) {
      send sender, ePong;
    }
  }
}
```

safety は monitor に置く。

```p
spec PingPongBalance observes ePing, ePong {
  var pendingPings: int;

  start state Watching {
    on ePing do { pendingPings = pendingPings + 1; }
    on ePong do {
      assert pendingPings > 0;
      pendingPings = pendingPings - 1;
    }
  }
}
```

repo の実行:

```sh
cd languages/p/PingPong
p compile
p check --schedules 1000
```

## 出力の読み方

| 出力 | 意味 |
| --- | --- |
| Found 0 bugs | 探索した schedule では monitor violation がない |
| bug trace | どの event schedule で assert が破れたか |
| compile error | P の syntax / module / reserved keyword の問題 |

## レシピ

### request / response protocol

置き換える作業:

- mock だらけの service 間 protocol test

モデル:

- client machine
- server machine
- timeout event
- retry event
- monitor

検査:

```text
response は request より前に来ない
retry しても成功 response は高々1回
```

### worker pool と queue

モデル:

- queue manager machine
- worker machine
- job events
- ack / fail events

検査:

```text
job が同時に2 workerへ assign されない
ack 済み job は再実行されない
```

### saga / compensating action

モデル:

- payment machine
- inventory machine
- shipment machine
- saga coordinator

検査:

```text
shipment 失敗時には payment が refund される
refund 後に shipment success が来ても paid+shipped の不整合にならない
```

## 避ける使い方

- 純粋 predicate の検査だけを P で書く
- domain relation だけの問題を state machine にしすぎる
- monitor なしで「走ったから OK」とする
- schedule 数を固定せず、CI の結果が揺れる状態にする

近い repo 例:

- [`../../languages/p/PingPong/`](../../languages/p/PingPong/)
