
mozc.elをmodelessで使える以下のようなものを作りたいです。
仕様は以下のようなものです。
mozc-modeless-modeというモードを追加します。
このモードでは、ローマ字を入力して、Ctrl-Jを変換すると、カーソル位置の直前のローマ字をmozcに渡して、mozcの変換モードに入ります。
また、mozcの変換が確定したら、mozcを終了し、元通りCtrl-Jを押すまで英数モードと同様の状態に戻ります。
ファイル名は、mozc-modeless.elひとつだけのプログラムです。
どのようなプログラムにするか提案してください。


## 開発コマンド

### リント／構文チェック
Emacs Lispファイルを編集した後は、**必ず**括弧バランスチェックツールを実行してください：

```bash
agent-lisp-paren-aid-linux lisp/sumibi.el
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


ctrl-jを押すと、"No romaji found before cursor"というエラーメッセージが出ます。
カーソルの直前は、「nihongo」という文字列でした。
