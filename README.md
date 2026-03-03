# mozc-modeless.el

Emacs用のモードレス日本語入力インターフェースです。
通常は英数入力で、`C-j` を押したときだけカーソルの直前のローマ字文字列をMozcに渡してMozcの変換モードに入ります。

> **より賢いモードレス日本語入力をお探しの方へ:**
> LLMを使った高度な日本語入力を体験したい場合は、[Sumibi](https://github.com/kiyoka/Sumibi)をご検討ください。AIによる文脈を考慮した変換候補の提供など、より洗練された入力体験を実現しています。

https://github.com/user-attachments/assets/371714d6-369c-486e-903f-13aaa434f144

## 特徴

- **モードレス入力**: IMEのON/OFF切り替え不要
- **自動復帰**: 変換確定後、自動的に英数モードに戻る
- **キャンセル対応**: `C-g`で元のローマ字を復元

## 必要環境

- Emacs 29.0以上
- mozc.el
- markdown-modeのインストール

## インストール

**注意**: Emacs 29.0以上が必要です。

### 方法1: package-vc-install を使う（推奨）

Emacs 29以降では、`package-vc-install`でGitHubから直接インストールできます。

- 事前に以下を`*scratch*`バッファで実行してinstallしてください

```elisp
(package-vc-install
  '(mozc-modeless . (:url "https://github.com/kiyoka/mozc-modeless-emacs.git")))
```

- init.elに追記してください

```elisp
(use-package mozc-modeless
  :config
  (global-mozc-modeless-mode 1))
```

### 方法2: 手動でインストール

- 事前準備

```bash
mkdir -p ~/.emacs.d/site-lisp/
cd ~/.emacs.d/site-lisp/
git clone https://github.com/kiyoka/mozc-modeless-emacs.git
```

- init.elに追記してください

```elisp
(add-to-list 'load-path "~/.emacs.d/site-lisp/mozc-modeless-emacs")
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

### アンビエント変換（自動変換）

助詞＋スペースや句読点の入力をトリガーに、自動的にmozc変換を実行する機能です。Mozcの第1候補で自動確定し、タイピングの流れを中断しません。デフォルトは無効です。

```elisp
;; 有効化
(setq mozc-modeless-ambient-enable t)
```

```
入力: "nihonga " (スペース入力) → "日本が"
入力: "wakarimashita."          → "わかりました。"
```

英文（英単語率80%以上）は自動的にスキップされ、誤変換を防ぎます。

#### カスタマイズ変数

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `mozc-modeless-ambient-enable` | `nil` | アンビエント変換の有効/無効 |
| `mozc-modeless-ambient-particles` | `("wa" "ha" "ga" ...)` | 変換トリガーとなる助詞リスト |
| `mozc-modeless-ambient-punctuation` | `("." "," "?")` | 変換トリガーとなる句読点リスト |
| `mozc-modeless-ambient-punctuation-auto-confirm` | `t` | `t`: 句読点入力時に第1候補で自動確定 / `nil`: 候補選択モードで止まる |
| `mozc-modeless-ambient-english-threshold` | `0.8` | 英文判定の閾値（0.0〜1.0） |
| `mozc-modeless-ambient-exclude-modes` | `(shell-mode term-mode eshell-mode)` | アンビエント変換を無効にするモード |
