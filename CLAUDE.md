## mozc-modeless.el 仕様書

### 概要
mozc.el を利用した modeless 日本語入力環境を提供する Emacs Lisp パッケージ。

### コンセプト
通常は英数入力モードで動作し、必要な時だけ日本語変換を行う「モードレス」な入力方式を実現する。

### 基本動作

1. **通常状態**
   - 英数字がそのまま入力される（通常のEmacs動作）

2. **変換開始** (`C-j`)
   - カーソル直前のローマ字列を検出
   - ローマ字を削除し、mozc に渡して変換モードに入る

3. **変換確定後**
   - 自動的に英数入力モードに戻る
   - 次の `C-j` まで日本語入力は行われない

### キーバインド

| キー | 動作 |
|------|------|
| `C-j` | 直前のローマ字を変換開始 |
| `C-g` | 変換キャンセル（元のローマ字を復元） |

### 使用例

```
入力: "hello nihongo"  + C-j
結果: "hello 日本語"   (自動的に英数モードに戻る)
```

### 依存関係
- mozc.el

### ファイル構成
- `mozc-modeless.el` （単一ファイル）


## 開発コマンド

### リント／構文チェック
Emacs Lispファイルを編集した後は、**必ず**括弧バランスチェックツールを実行してください：

```bash
agent-lisp-paren-aid-linux mozc-modeless.el
```

## mozc-modeless.el の設計提案

### 概要
modelessなIMEインターフェースを実現するEmacs Lispプログラムです。通常は英数入力で、`C-j`キーで直前のローマ字をMozcで変換します。

### 主な機能設計

#### 1. **基本構造**
```
- mozc-modeless-mode: マイナーモード
- 通常状態: 英数入力（直接入力）
- C-j押下 → 変換モード → 確定 → 通常状態に戻る
```

#### 2. **実装アプローチ（2つの案）**

**【案A】mozc.elに依存する方式（推奨）**
- 既存のmozc.elの機能を活用
- メリット：
  - 実装がシンプル（200-300行程度）
  - mozcサーバー通信が安定
  - 候補表示UIを再利用可能
- デメリット：
  - mozc.elが必要

**【案B】独立実装方式**
- mozcサーバーと直接プロセス通信
- メリット：
  - 依存なし、独立動作
  - 完全にカスタマイズ可能
- デメリット：
  - 実装量が多い（500-800行程度）
  - mozcプロトコルの実装が必要

#### 3. **主要な機能**

```elisp
;; コア機能
(define-minor-mode mozc-modeless-mode
  "Modeless Japanese input using Mozc.")

(defun mozc-modeless-convert ()
  "C-jで呼び出される変換開始関数"
  ;; 1. 直前のローマ字を取得
  ;; 2. その範囲を削除
  ;; 3. mozcで変換開始
  ;; 4. 変換確定後、通常モードに戻る
  )

(defun mozc-modeless--get-preceding-roman ()
  "カーソル直前のローマ字文字列を取得"
  ;; [a-zA-Z]+ のパターンで後方検索
  )
```

#### 4. **技術的なポイント**

**ローマ字の検出**
- 正規表現で `[a-zA-Z]+` を後方検索
- 単語境界：空白、句読点、改行など
- 例: `hello world konna` → カーソル位置から `konna` を抽出

**変換モードの実装**
- 一時的なキーマップを設定
- 変換中のキー: SPC（次候補）、C-n/C-p（選択）、RET（確定）、C-g（キャンセル）
- overlayで候補を表示

**状態管理**
```elisp
(defvar mozc-modeless--active nil
  "変換モードが有効かどうか")
```

#### 5. **ファイル構成（案A推奨）**

```elisp
;;; mozc-modeless.el --- Modeless Japanese input with Mozc

;; 依存関係
(require 'mozc)  ; 既存のmozc.el

;; カスタマイズ変数
(defgroup mozc-modeless nil ...)

;; 内部変数
(defvar mozc-modeless--active nil)
(defvar mozc-modeless--start-pos nil)

;; ユーティリティ関数
(defun mozc-modeless--get-preceding-roman () ...)

;; メイン機能
(defun mozc-modeless-convert () ...)
(defun mozc-modeless--finish () ...)

;; マイナーモード定義
(define-minor-mode mozc-modeless-mode
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-j") 'mozc-modeless-convert)
            map))
```

### 推奨する実装の流れ

1. **基本骨格の作成**（mozc.elへの依存を前提）
2. **ローマ字検出機能**
3. **mozc連携機能**（既存APIのラッパー）
4. **変換UI**（overlayベース）
5. **状態管理とクリーンアップ**

### 質問

実装を進める前に確認させてください：

1. **依存関係**: 既存のmozc.elに依存する「案A」で良いでしょうか？
2. **変換キャンセル**: `C-g`でキャンセルした場合、ローマ字を元に戻しますか？
3. **変換範囲**: ローマ字のみ対象ですか？それとも既に入力された日本語も含めますか？


1. **依存関係**: 既存のmozc.elに依存する「案A」で良いでしょうか？ yes
2. **変換キャンセル**: `C-g`でキャンセルした場合、ローマ字を元に戻しますか？ yes
3. **変換範囲**: ローマ字のみ対象ですか？それとも既に入力された日本語も含めますか？ ローマ字のみが対象です。

## 実装内容

### ファイル: mozc-modeless.el

mozc.elに依存する形でmodelessなIMEを実装しました。

#### 実装した主要機能

1. **マイナーモード定義** (mozc-modeless.el:161-180)
   - `mozc-modeless-mode`: グローバルまたはバッファローカルで有効化可能
   - ライター表示: " Mozc-ML"
   - 有効化時にmozc.elの存在をチェック

2. **カスタマイズ変数** (mozc-modeless.el:45-58)
   - `mozc-modeless-roman-regexp`: ローマ字検出用の正規表現 (デフォルト: `[a-zA-Z]+`)
   - `mozc-modeless-convert-key`: 変換トリガーキー (デフォルト: `C-j`)

3. **内部状態管理** (mozc-modeless.el:60-72)
   - `mozc-modeless--active`: 変換モードが有効かどうか
   - `mozc-modeless--start-pos`: ローマ字の開始位置
   - `mozc-modeless--original-string`: キャンセル時の復元用

4. **ローマ字検出** (mozc-modeless.el:76-86)
   - `mozc-modeless--get-preceding-roman`: カーソル直前のローマ字を検出
   - 行頭から現在位置までを検索範囲とする
   - 戻り値: `(開始位置 . ローマ字文字列)` または nil

5. **変換開始** (mozc-modeless.el:90-114)
   - `mozc-modeless-convert`: C-jにバインドされたメイン関数
   - 処理フロー:
     1. ローマ字検出
     2. 元の文字列を保存
     3. ローマ字を削除
     4. mozc input-methodを有効化
     5. mozcに文字列を送信
     6. 変換完了検知のフック設定

6. **変換終了処理** (mozc-modeless.el:128-142)
   - `mozc-modeless--finish`: 変換確定後のクリーンアップ
   - input-methodの無効化
   - 内部状態のリセット
   - フックの削除

7. **キャンセル機能** (mozc-modeless.el:144-157)
   - `mozc-modeless-cancel`: C-gにバインド
   - mozc変換のキャンセル
   - 元のローマ字を復元
   - 状態のクリーンアップ

#### キーバインド

- `C-j`: `mozc-modeless-convert` - 変換開始
- `C-g`: `mozc-modeless-cancel` - キャンセルと復元

#### 使用方法

```elisp
;; .emacsまたはinit.elに追加
(require 'mozc-modeless)
(mozc-modeless-mode 1)

;; 使い方:
;; 1. 通常通りローマ字を入力 (例: "konnnichiwa")
;; 2. C-j を押すと mozc変換開始
;; 3. スペースで候補選択、Enterで確定
;; 4. 確定後、自動的に英数モードに戻る
;; 5. C-g でキャンセルして元のローマ字に戻る
```

#### 注意事項と今後の課題

**mozc.el APIの不確実性:**

現在の実装は、以下のmozc.el APIを仮定しています：
- `mozc-handle-event`: イベント処理
- `mozc-in-conversion-p`: 変換中かどうかの判定
- `mozc-handle-event-after-insert-hook`: 挿入後のフック
- `mozc-cancel`: 変換キャンセル

**これらのAPIが実際のmozc.elに存在しない可能性があります。**

実際に動作させるには：
1. システムにインストールされているmozc.elのソースコードを確認
2. 正しいAPI仕様に合わせてコードを修正
3. 実際に動作テストを実施

#### 代替実装案

mozc.elの内部APIが使えない場合、以下の代替アプローチが考えられます：

1. **シンプルなinput-method切り替え方式**
   - `activate-input-method` / `deactivate-input-method` のみ使用
   - キーイベントを `unread-command-events` で送信
   - より移植性が高い

2. **overlay を使った独自UI**
   - mozcサーバーと直接通信
   - 候補表示を独自実装
   - 完全な制御が可能だが実装量が多い

#### 次のステップ

1. mozc.elの実際のAPIドキュメント・ソースコードを確認
2. 必要に応じてAPIの使い方を修正
3. 実際の動作テストと調整
4. エッジケースの処理追加（複数行、特殊文字など）

### GitHub Issue #5 対応: markdown-mode でのmarkdown構文除外

#### 問題の概要

markdown-modeで使用時、markdownの構文記号（リスト記号、見出し記号など）が変換対象に含まれてしまう問題がありました。

**具体例:**
```
入力: "- aitemu" + C-j
現在の結果: "ーアイテム"  ← リスト記号"-"が長音符"ー"に変換されてしまう
期待する結果: "- アイテム"  ← リスト記号"-"は変換せず、"aitemu"だけを変換
```

#### 実装内容 (2025-12-03)

`mozc-modeless--get-preceding-roman` 関数を修正して、markdown-mode時にmarkdown構文を認識し、変換対象から除外するようにしました。

**主な変更点:**

1. **markdown-modeの検出**
   - `derived-mode-p` を使ってmarkdown-modeかどうかをチェック

2. **markdown構文の認識**
   - リスト記号: markdown-modeの `markdown-regex-list` を使用して `-`, `*`, `+`, `1.` などを認識
   - 見出し記号: 正規表現 `^[ \t]*\\(#+\\)[ \t]+` で `#`, `##` などを認識

3. **変換範囲の調整**
   - markdown構文が検出された場合、その後の位置から変換対象の検索を開始
   - これにより、markdown構文自体は変換対象から除外される

4. **依存関係の追加**
   - Package-Requires に `(markdown-mode "2.0")` を追加

**修正ファイル:**
- `mozc-modeless.el:79-105` - `mozc-modeless--get-preceding-roman` 関数
- `mozc-modeless.el:8` - Package-Requires

**動作例:**
```
入力: "- aitemu" + C-j
結果: "- アイテム"

入力: "## midashi" + C-j
結果: "## 見出し"
```

**参考資料:**
- [markdown-mode公式ドキュメント](https://jblevins.org/projects/markdown-mode/)
- [markdown-mode GitHub リポジトリ](https://github.com/jrblevin/markdown-mode)

### GitHub Issue #6 対応: インデントの維持

#### 問題の概要

Ctrl-Jで変換を開始すると、行頭のインデント（空白やタブ文字）も変換対象に含まれてしまい、インデント構造が崩れる問題がありました。

**具体例:**
```
入力: "    konnnichiwa" + C-j  (行頭に4つの空白)
問題: 空白も変換対象に含まれる可能性
期待する結果: "    こんにちは"  (インデントは保持)
```

#### 実装内容 (2025-12-03)

`mozc-modeless--get-preceding-roman` 関数を修正して、行頭のインデント（空白・タブ文字）を変換対象から除外するようにしました。

**主な変更点:**

1. **行頭インデントのスキップ**
   - `skip-chars-forward " \t"` を使って行頭の空白・タブをスキップ
   - スキップ後の位置から変換対象の検索を開始

2. **処理順序の調整**
   - まず行頭のインデントをスキップ
   - その後、markdown-modeの構文チェック（issue #5の機能）を実行
   - これにより、インデント付きのmarkdown構文も正しく処理される

3. **すべてのモードで有効**
   - この機能はmarkdown-mode専用ではなく、すべてのモードで動作
   - プログラムコードの編集時にも有用

**修正ファイル:**
- `mozc-modeless.el:79-111` - `mozc-modeless--get-preceding-roman` 関数

**動作例:**
```
入力: "    konnnichiwa" + C-j
結果: "    こんにちは"  (インデント保持)

入力: "        - aitemu" + C-j  (markdown-modeでインデント付きリスト)
結果: "        - アイテム"  (インデントとリスト記号の両方を保持)
```

**技術詳細:**
- 行頭から `skip-chars-forward " \t"` でインデント部分をスキップ
- `search-start` をインデント後の位置に設定
- markdown構文チェックは `search-start` から開始するため、インデント後の構文を正しく認識

質問です。

 mozc-modelessでバッファ上に"質問"のような日本語変換済みの文字列が存在する状態から、再度mozcの変換状態に戻る方法はありますか？
つまり，"質問"という文字列をmozcに渡しながらmozcの変換状態に入ることは可能でしょうか？

提案された方法は、"しつもん"という文字列が入手できているように書かれていますが、それはどこから得られる想定ですか？

### リージョン選択による変換機能の実験 (2025-12-13) - 失敗

#### 実験の背景

バッファ上に既に存在する日本語文字列（例："質問"）を再度mozcの変換状態に戻して、別の候補を選択したいという要望から、リージョン選択した文字列をmozcに渡す機能を実験的に実装しました。

#### 実装方針

- リージョンが選択されている場合、その文字列をmozcに渡す
- `listify-key-sequence`で文字列をイベントに変換して`unread-command-events`に追加

#### 実験結果：全て失敗

| テストケース | 入力 | 期待結果 | 実際の結果 |
|------------|------|---------|----------|
| 日本語（漢字） | 「質問」を選択 + C-j | 変換候補表示 | ✗ スペースのみ残る |
| ひらがな | 「しつもん」を選択 + C-j | 「質問」等に変換 | ✗ スペースのみ残る |
| ローマ字 | 「sitsumon」を選択 + C-j | 「しつもん」に変換 | ✗ スペースのみ残る |

**動作例:**
```
入力: 「あああ質問あああ」
操作: 「質問」を選択してC-j
結果: 「あああ　あああ」（質問が消えてスペースだけが残る）
```

**C-gでのキャンセル:** 元の文字列が復元されない（これも不具合）

#### 失敗の原因

`listify-key-sequence`が日本語文字（マルチバイト文字）を正しく処理できず、選択した文字列がmozcに渡されていない。最後に追加したスペースだけが入力される状態。

#### 結論

**この実装方式では日本語文字列の再変換は実現不可能。**

実装をロールバックしてバージョン0.4.0の状態に戻しました。

#### 今後の方向性

日本語文字列の再変換を実現するには、以下のような別のアプローチが必要：
- mozc.elの再変換API（もし存在すれば）を直接利用
- 日本語→ひらがな変換ライブラリ（kakasi等）を使用して読みを取得
- mozcサーバーと直接プロトコル通信

現時点では実装を見送り。

### GitHub Issue #10 対応: Lisp Interactionモードでの式評価

#### 問題の概要

Lisp Interactionモード（*scratch*バッファなど）では、通常Ctrl-Jは`eval-print-last-sexp`（S式を評価して結果を表示）として使われます。しかし、mozc-modelessが有効な場合、常にローマ字変換を試みるため、Lisp式の評価ができなくなっていました。

**要望:**
- Lisp Interactionモードで、Ctrl-J押下時にカーソルの直前が「)」（閉じ括弧）の場合は、mozc変換ではなく、Lisp式を評価する動作としてほしい

#### 実装内容 (2025-12-13)

`mozc-modeless-convert`関数の冒頭で、lisp-interaction-modeかどうかと、カーソル直前の文字が「)」かどうかをチェックし、両方に該当する場合は元のCtrl-Jの動作を実行するようにしました。

**主な変更点:**

1. **lisp-interaction-modeのチェック**
   - `(derived-mode-p 'lisp-interaction-mode)` でモードを判定
   - `(eq (char-before) 41)` でカーソル直前の文字が「)」(ASCII 41)かどうかをチェック

2. **条件分岐の追加**
   - lisp-interaction-modeかつカーソル直前が「)」の場合: `eval-print-last-sexp`を実行
   - それ以外の場合: 通常のmozc変換を実行

3. **emacs-lisp-modeへの対応**
   - 調査の結果、emacs-lisp-modeではCtrl-Jは`newline-and-indent`（改行とインデント）
   - S式の評価には`C-x C-e`（`eval-last-sexp`）や`C-M-x`（`eval-defun`）を使用
   - したがって、emacs-lisp-modeは対象外とし、lisp-interaction-modeのみに対応

**修正ファイル:**
- `mozc-modeless.el:152-198` - `mozc-modeless-convert`関数の修正
- `mozc-modeless.el:150-151` - docstringの更新

**動作例:**
```
Lisp Interactionモードでの動作:

入力: "(+ 1 2)" + Ctrl-J
結果: S式が評価されて "3" が表示される

入力: "nihongo" + Ctrl-J
結果: "日本語" に変換される（通常のmozc変換）
```

**技術詳細:**
- 文字リテラル`?\)`ではなく、ASCII コード`41`を使用して括弧をチェック
- `cond`を使用して3つの条件分岐を明確化：
  1. lisp-interaction-modeで閉じ括弧の直後 → S式評価
  2. 既に変換モード中 → 次候補へ
  3. それ以外 → 通常の変換開始
- ネストした`if`ではなく`cond`を使用することで、可読性を向上

### GitHub Issue #13 対応: 変換中のCtrlキーバインド追加

#### 問題の概要

mozc変換中に、Emacsの標準的なカーソル移動キー（Ctrl+N、Ctrl+P、Ctrl+F、Ctrl+B）を使って候補選択や文節移動を行いたいという要望がありました。

**要望内容:**
1. **Ctrl+N** → 次の候補を選択
2. **Ctrl+P** → 前の候補を選択
3. **Ctrl+F** → 次の文節に移動
4. **Ctrl+B** → 前の文節に移動

#### 調査結果 (2026-01-03)

**mozc.elのキーイベント処理の仕組み:**

1. mozc-mode-mapは`[t]`（すべてのキー）を`mozc-handle-event`にバインド (mozc.el:174)
2. `mozc-handle-event`はすべてのキーイベントをmozcサーバーに送信 (mozc.el:327-374)
3. mozcサーバー側で対応しているキーは`consumed=true`を返し、対応していないキーは`consumed=false`を返す
4. `consumed=false`のキーはEmacsのデフォルトキーバインドにフォールバック

**現状:**
- Ctrl+Nはmozcサーバー側でサポートされているが、特別な意味（確定動作）を持つため、矢印キーと異なる動作をする
- Ctrl+P、Ctrl+F、Ctrl+Bはmozcサーバー側で未サポート

#### 実装内容 (2026-01-03)

mozc-modeless側で、変換中に有効な`mozc-modeless--converting-map`に4つのキーバインドを追加しました。

**追加した関数:** (mozc-modeless.el:254-276)

1. `mozc-modeless-previous-candidate` - Ctrl+P用
   - 上矢印キー（`up`）を`unread-command-events`に送信

2. `mozc-modeless-next-candidate` - Ctrl+N用
   - 下矢印キー（`down`）を`unread-command-events`に送信
   - mozcサーバー側のCtrl+Nの特別な意味を回避

3. `mozc-modeless-next-segment` - Ctrl+F用
   - 右矢印キー（`right`）を`unread-command-events`に送信

4. `mozc-modeless-previous-segment` - Ctrl+B用
   - 左矢印キー（`left`）を`unread-command-events`に送信

**キーマップの更新:** (mozc-modeless.el:71-79)

```elisp
(defvar mozc-modeless--converting-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-g") 'mozc-modeless-cancel)
    (define-key map (kbd "C-n") 'mozc-modeless-next-candidate)
    (define-key map (kbd "C-p") 'mozc-modeless-previous-candidate)
    (define-key map (kbd "C-f") 'mozc-modeless-next-segment)
    (define-key map (kbd "C-b") 'mozc-modeless-previous-segment)
    map)
  "Keymap active only during conversion.")
```

**動作例:**
```
変換中の操作:

入力: "konnnichiwa" + Ctrl-J
変換開始: 「こんにちわ」

Ctrl+N: 次の候補「今日は」（mozc-modeless側で下矢印を送信）
Ctrl+P: 前の候補「こんにちわ」（mozc-modeless側で上矢印を送信）
Ctrl+F: 次の文節に移動（mozc-modeless側で右矢印を送信）
Ctrl+B: 前の文節に移動（mozc-modeless側で左矢印を送信）
```

**技術詳細:**
- 矢印キーのシミュレーションには、シンボル（`'down`、`'up`、`'right`、`'left`）を`unread-command-events`に追加
- これらのキーは`mozc-handle-event`を経由してmozcサーバーに渡される
- mozcサーバーは矢印キーを適切に処理（候補選択、文節移動）
- `mozc-modeless--converting-map`は`set-transient-map`により変換中のみ有効 (mozc-modeless.el:203-204)

**Ctrl+Nの特別な扱い:**
- mozcサーバー側のCtrl+Nは、確定動作など特別な意味を持つ
- Ctrl+Pを押した後にCtrl+Nを押すと確定してしまう問題があった
- mozc-modeless側でCtrl+Nを下矢印キーに変換することで、この問題を回避

### GitHub Issue #20 対応: アンビエント変換（自動変換）

#### 問題の概要

従来、日本語変換はC-jの明示的な押下でのみ開始されていました。Sumibiのアンビエント変換を参考に、助詞＋スペースや句読点入力をトリガーに自動的にmozc変換を実行する機能を追加しました。変換はmozcの第1候補で自動確定し、タイピングの流れを中断しません。

**要望:**
- 助詞（「wa」「ga」「ni」等）の後にスペースを入力すると自動変換
- 句読点（`.` `,` `?`）の入力で自動変換＋全角句読点挿入
- 英文入力時はスキップ（誤変換防止）
- デフォルトは無効（ユーザーが明示的に有効化）

#### 実装内容 (2026-03-03)

**新規ファイル: `mozc-modeless-english-words.el`**

Sumibiの`sumibi-english-words.el`（SCOWL辞書ベース、Public Domain）をコピー・リネームして作成。

- `mozc-modeless--english-words-hash`: 約3,679語の英単語ハッシュテーブル（3〜10文字）
- `mozc-modeless--english-word-p`: 英単語判定関数（O(1)ハッシュテーブル検索）
- ソース: SCOWL (Spell Checker Oriented Word Lists) Version 2020.12.07

**修正ファイル: `mozc-modeless.el` (v0.6.0 → v0.7.0)**

1. **カスタマイズ変数（5つ追加）** (mozc-modeless.el:53-81)
   - `mozc-modeless-ambient-enable` (default: `nil`) — アンビエント変換の有効/無効
   - `mozc-modeless-ambient-particles` — 助詞リスト: `("wa" "ha" "ga" "wo" "ni" "de" "to" "kara" "made" "he" "mo" "no" "ya" "desu")`
   - `mozc-modeless-ambient-punctuation` — 句読点リスト: `("." "," "?")`
   - `mozc-modeless-ambient-english-threshold` (default: 0.8) — 英文判定閾値
   - `mozc-modeless-ambient-exclude-modes` — 除外モードリスト: `(shell-mode term-mode eshell-mode)`

2. **英文検出機能** (mozc-modeless.el:320-348)
   - `mozc-modeless--short-english-words`: 短い英単語リスト（"I", "a", "is"等27語）
   - `mozc-modeless--normalize-word`: 末尾句読点の除去
   - `mozc-modeless--english-text-p`: メイン判定関数
     - テキストを空白で分割
     - 各単語を辞書・短単語リスト・固有名詞（大文字始まり）で判定
     - 英単語率 >= 80% なら英文と判定してスキップ

3. **助詞・句読点トリガー** (mozc-modeless.el:382-415)
   - `mozc-modeless--check-ambient-trigger`: `post-self-insert-hook`に登録
     - スペース入力時: 直前テキストが助詞で終わるか判定
     - 句読点入力時: 直前にローマ字があるか判定
     - 英文検出で80%以上ならスキップ
     - 除外モード・ミニバッファ・変換中はスキップ
   - `mozc-modeless--ends-with-particle-p`: 助詞末尾検出（孤立した助詞はスキップ）
   - `mozc-modeless--ambient-excluded-p`: 除外条件判定

4. **自動変換・自動確定** (mozc-modeless.el:417-446)
   - `mozc-modeless--ambient-convert`: アンビエント変換実行
     - ローマ字を削除し、mozc input-methodを有効化
     - ローマ字＋スペース＋Enter（自動確定）を`unread-command-events`に送信
     - `post-command-hook`でpreedit消失を検知してクリーンアップ
     - 句読点トリガーの場合、確定後に全角句読点を挿入
   - `mozc-modeless--to-fullwidth-punctuation`: 句読点の全角変換（`.`→`。`, `,`→`、`, `?`→`？`）

5. **フック管理** (mozc-modeless.el:496-509)
   - `mozc-modeless-mode`の有効化時に`post-self-insert-hook`に`mozc-modeless--check-ambient-trigger`を追加
   - 無効化時にフックを削除

**既存の`mozc-modeless-convert`（C-j）との違い:**
- transient-keymapを設定しない（候補選択UIなし）
- `mozc-modeless--active`をセットしない（C-gキャンセル不要）
- 自動確定のためEnterキーイベントを追加送信
- `mozc-modeless--ambient-in-progress`フラグで再帰トリガーを防止

**動作例:**
```
;; 有効化
(setq mozc-modeless-ambient-enable t)

;; 助詞＋スペーストリガー
入力: "nihonga " (スペース入力)
結果: "日本が"  ← 自動変換＋自動確定

;; 句読点トリガー
入力: "wakarimashita."
結果: "わかりました。" ← 自動変換＋全角句読点

;; 英文はスキップ
入力: "I will not create a pull request "
結果: "I will not create a pull request " ← そのまま（英文80%以上）

;; shell-modeでは無効
shell-mode: コマンド入力中にアンビエント変換は発動しない
```

**依存関係の追加:**
- `mozc-modeless-english-words.el`を`require`で読み込み (mozc-modeless.el:39)

コミットしてください。
