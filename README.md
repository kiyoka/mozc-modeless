# mozc-modeless.el

Emacs用のモードレス日本語入力パッケージ。通常は英数入力、`C-j`で直前のローマ字をMozcで変換。

## 特徴

- **モードレス入力**: IMEのON/OFF切り替え不要
- **自動復帰**: 変換確定後、自動的に英数モードに戻る
- **キャンセル対応**: `C-g`で元のローマ字を復元

## 必要環境

- Emacs 29.0以上
- mozc.el

## インストール

```elisp
(add-to-list 'load-path "/path/to/mozc-modeless")
(require 'mozc-modeless)
(global-mozc-modeless-mode 1)
```

## 使い方

1. ローマ字を入力: `nihongo`
2. `C-j` を押す → 変換候補表示
3. `C-j` または `SPC` で候補選択、`RET` で確定
4. 自動的に英数モードに戻る

キャンセルは `C-g`（元のローマ字を復元）

### スラッシュ区切り

`/` を使うと、その後ろの部分だけを変換できます。

```
入力: "日本語/ga" + C-j → "日本語が"
入力: "hello/world/nihongo" + C-j → "hello/world日本語"
```

`/` は変換時に自動削除されます。
