;;; mozc-modeless.el --- Modeless Japanese input with Mozc  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Kiyoka Nishiyama
;; Keywords: i18n, extentions
;; Version: 0.7.0
;; Package-Requires: ((emacs "29.0") (mozc "0") (markdown-mode "2.0"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; mozc-modeless.el provides a modeless Japanese input interface using Mozc.
;;
;; Usage:
;;   (require 'mozc-modeless)
;;   (global-mozc-modeless-mode 1)
;;
;; By default, you type in alphanumeric mode. When you want to convert
;; the preceding romaji to Japanese, press C-j. This will activate Mozc
;; conversion mode. After you confirm the conversion, the mode automatically
;; returns to alphanumeric input.

;;; Code:

(require 'mozc)
(require 'mozc-modeless-english-words)

;;; Customization

(defgroup mozc-modeless nil
  "Modeless Japanese input with Mozc."
  :group 'mozc
  :prefix "mozc-modeless-")

(defcustom mozc-modeless-convert-key (kbd "C-j")
  "Key sequence to trigger conversion."
  :type 'key-sequence
  :group 'mozc-modeless)

(defcustom mozc-modeless-ambient-enable nil
  "Non-nil to enable ambient (automatic) conversion.
When enabled, typing a particle followed by space or punctuation
automatically triggers Mozc conversion."
  :type 'boolean
  :group 'mozc-modeless)

(defcustom mozc-modeless-ambient-particles
  '("wa" "ha" "ga" "wo" "ni" "de" "to" "kara" "made" "he" "mo" "no" "ya" "desu")
  "List of romaji particles that trigger ambient conversion when followed by space."
  :type '(repeat string)
  :group 'mozc-modeless)

(defcustom mozc-modeless-ambient-punctuation '("." "," "?")
  "List of punctuation characters that trigger ambient conversion."
  :type '(repeat string)
  :group 'mozc-modeless)

(defcustom mozc-modeless-ambient-english-threshold 0.8
  "Threshold for English text detection.
If the ratio of English words in the preceding text is greater than
or equal to this value, ambient conversion is skipped."
  :type 'float
  :group 'mozc-modeless)

(defcustom mozc-modeless-ambient-exclude-modes '(shell-mode term-mode eshell-mode)
  "List of major modes where ambient conversion is disabled."
  :type '(repeat symbol)
  :group 'mozc-modeless)

(defvar mozc-modeless-skip-chars "a-zA-Z0-9.,@:`\\-+!/\\[\\]?;' \t"
  "Characters to be included in the preceding string for conversion.
Includes slash (/) as a delimiter for partial conversion.")

;;; Internal variables

(defvar mozc-modeless--active nil
  "Non-nil when Mozc conversion mode is active.")

(defvar mozc-modeless--start-pos nil
  "Buffer position where the romaji string started.")

(defvar mozc-modeless--original-string nil
  "Original romaji string before conversion.
This is used to restore the text when conversion is cancelled.")

(defvar mozc-modeless--skip-check-count 0
  "Number of post-command-hook calls to skip before checking finish.")

(defvar mozc-modeless--converting-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-g") 'mozc-modeless-cancel)
    (define-key map (kbd "C-n") 'mozc-modeless-next-candidate)
    (define-key map (kbd "C-p") 'mozc-modeless-previous-candidate)
    (define-key map (kbd "C-f") 'mozc-modeless-next-segment)
    (define-key map (kbd "C-b") 'mozc-modeless-previous-segment)
    map)
  "Keymap active only during conversion.")

;;; Utility functions

(defun mozc-modeless--get-preceding-roman ()
  "Get the preceding romaji string before the cursor.
Returns a cons cell (START . STRING) where START is the beginning
position of the romaji string, or nil if no romaji is found.
Leading indentation (spaces and tabs) at the beginning of the line
are excluded from the conversion target.
In markdown-mode, markdown syntax (list markers using markdown-regex-list,
headings) are excluded. In text-mode and fundamental-mode, markdown syntax
is also recognized using built-in regex patterns."
  (save-excursion
    (let* ((end (point))
           (line-start (line-beginning-position))
           (search-start line-start))
      ;; Skip leading indentation (spaces and tabs)
      (goto-char line-start)
      (skip-chars-forward " \t")
      (setq search-start (point))
      ;; Skip markdown syntax in markdown-mode, text-mode, and fundamental-mode
      (cond
       ;; In markdown-mode, use markdown-regex-list if available
       ((and (derived-mode-p 'markdown-mode)
             (boundp 'markdown-regex-list))
        (save-excursion
          (goto-char search-start)
          ;; Check for list markers (-, *, +, 1., etc.)
          (when (looking-at markdown-regex-list)
            (setq search-start (match-end 0)))
          ;; Check for ATX headings (#, ##, etc.)
          (goto-char search-start)
          (when (looking-at "^\\(#+\\)[ \t]+")
            (setq search-start (max search-start (match-end 0))))))
       ;; In text-mode or fundamental-mode, use our own regex
       ((or (derived-mode-p 'text-mode)
            (derived-mode-p 'fundamental-mode))
        (save-excursion
          (goto-char search-start)
          ;; Check for list markers (-, *, +, 1., etc.)
          (when (looking-at "\\([-*+]\\|[0-9]+\\.\\)[ \t]+")
            (setq search-start (match-end 0)))
          ;; Check for ATX headings (#, ##, etc.)
          (goto-char search-start)
          (when (looking-at "\\(#+\\)[ \t]+")
            (setq search-start (match-end 0))))))
      ;; Skip backward over characters defined in mozc-modeless-skip-chars
      (goto-char end)
      (skip-chars-backward mozc-modeless-skip-chars search-start)
      (when (< (point) end)
        (cons (point) (buffer-substring-no-properties (point) end))))))

;;; Main functions

(defun mozc-modeless--reset-state ()
  "Reset all internal state variables and remove hooks."
  (setq mozc-modeless--active nil
        mozc-modeless--start-pos nil
        mozc-modeless--original-string nil
        mozc-modeless--skip-check-count 0)
  (remove-hook 'post-command-hook #'mozc-modeless--check-finish t))

(defun mozc-modeless--deactivate-ime ()
  "Deactivate mozc input method if it's currently active."
  (when (and current-input-method
             (string= current-input-method "japanese-mozc"))
    (deactivate-input-method)))

(defun mozc-modeless-convert ()
  "Convert the preceding romaji string to Japanese using Mozc.
This function is bound to `mozc-modeless-convert-key' (default: C-j).
When already in conversion mode, switch to the next candidate.
If the string contains a slash (/), only the part after the last slash
is sent to mozc, and the slash is deleted.
In lisp-interaction-mode, if the preceding character is ')', evaluate
the expression instead of converting."
  (interactive)
  (cond
   ;; In lisp-interaction-mode, evaluate the expression if preceding char is ')'
   ((and (derived-mode-p 'lisp-interaction-mode)
         (eq (char-before) 41))
    (call-interactively 'eval-print-last-sexp))

   ;; Already in conversion mode, send space to get next candidate
   (mozc-modeless--active
    (setq unread-command-events (cons ?\s unread-command-events)))

   ;; Start conversion
   (t
    (let ((roman-data (mozc-modeless--get-preceding-roman)))
      (if (not roman-data)
          (message "No romaji found before cursor")
        (let* ((start (car roman-data))
               (full-string (cdr roman-data))
               (slash-pos (string-match-p "/[^/]*$" full-string))
               (roman-string (if slash-pos
                                 (substring full-string (1+ slash-pos))
                               full-string))
               (delete-start (if slash-pos
                                 (+ start slash-pos)
                               start)))
          ;; Check if there's actually something to convert after the slash
          (if (string-empty-p roman-string)
              (message "No romaji found after slash")
            ;; Save state
            (setq mozc-modeless--active t
                  mozc-modeless--start-pos delete-start
                  mozc-modeless--original-string (if slash-pos
                                                     (substring full-string slash-pos)
                                                   full-string)
                  ;; Skip checking for a few commands to let mozc initialize
                  ;; +1 for the space key that triggers conversion
                  mozc-modeless--skip-check-count (1+ (length roman-string)))
            ;; Delete the romaji string (including slash if present)
            (delete-region delete-start (+ start (length full-string)))
            ;; Activate mozc input method
            (unless current-input-method
              (activate-input-method "japanese-mozc"))
            ;; Set up hook to detect conversion completion
            (add-hook 'post-command-hook #'mozc-modeless--check-finish nil t)
            ;; Activate transient keymap for C-g during conversion
            (set-transient-map mozc-modeless--converting-map
                               (lambda () mozc-modeless--active))
            ;; Insert the romaji string through mozc, followed by space to convert
            (mozc-modeless--insert-string (concat roman-string " ")))))))))

(defun mozc-modeless--insert-string (str)
  "Insert string STR through Mozc input method.
Queue characters to be processed by the active input method."
  (setq unread-command-events
        (append (listify-key-sequence str) unread-command-events)))

(defun mozc-modeless--preedit-active-p ()
  "Return non-nil if mozc has an active preedit session."
  (or (bound-and-true-p mozc-preedit-in-session-flag)
      (bound-and-true-p mozc-preedit-overlay)))

(defun mozc-modeless--check-finish ()
  "Check if conversion is finished and clean up if necessary.
This is called from `post-command-hook'."
  (when mozc-modeless--active
    (if (> mozc-modeless--skip-check-count 0)
        ;; Still processing initial romaji input
        (setq mozc-modeless--skip-check-count (1- mozc-modeless--skip-check-count))
      ;; Check if mozc is no longer in preedit/conversion state
      (unless (mozc-modeless--preedit-active-p)
        (mozc-modeless--finish)))))

(defun mozc-modeless--finish ()
  "Finish conversion mode and return to normal mode."
  (when mozc-modeless--active
    ;; Deactivate mozc input method
    (mozc-modeless--deactivate-ime)
    ;; Clean up state
    (mozc-modeless--reset-state)))

(defun mozc-modeless-cancel ()
  "Cancel the current conversion and restore the original romaji string."
  (interactive)
  (when mozc-modeless--active
    ;; Cancel mozc conversion by deactivating input method
    (mozc-modeless--deactivate-ime)
    ;; Delete any preedit text that mozc may have inserted
    (when (bound-and-true-p mozc-preedit-overlay)
      (delete-overlay mozc-preedit-overlay))
    ;; Clear preedit flag if it exists
    (when (boundp 'mozc-preedit-in-session-flag)
      (setq mozc-preedit-in-session-flag nil))
    ;; Restore original string
    (when (and mozc-modeless--start-pos mozc-modeless--original-string)
      (goto-char mozc-modeless--start-pos)
      (insert mozc-modeless--original-string))
    ;; Clean up state
    (mozc-modeless--reset-state)))

(defun mozc-modeless-previous-candidate ()
  "Select the previous candidate during conversion.
This function simulates the up arrow key."
  (interactive)
  (setq unread-command-events (cons 'up unread-command-events)))

(defun mozc-modeless-next-candidate ()
  "Select the next candidate during conversion.
This function simulates the down arrow key."
  (interactive)
  (setq unread-command-events (cons 'down unread-command-events)))

(defun mozc-modeless-next-segment ()
  "Move to the next segment during conversion.
This function simulates the right arrow key."
  (interactive)
  (setq unread-command-events (cons 'right unread-command-events)))

(defun mozc-modeless-previous-segment ()
  "Move to the previous segment during conversion.
This function simulates the left arrow key."
  (interactive)
  (setq unread-command-events (cons 'left unread-command-events)))

(defun mozc-modeless-reset ()
  "Reset mozc-modeless state.
Use this if the mode gets stuck in an inconsistent state."
  (interactive)
  (mozc-modeless--deactivate-ime)
  (mozc-modeless--reset-state)
  (message "mozc-modeless state reset"))

;;; Ambient conversion

(defvar mozc-modeless--short-english-words
  '("I" "a" "an" "am" "as" "at" "be" "by" "do" "go" "he" "if" "in"
    "is" "it" "me" "my" "no" "of" "on" "or" "so" "to" "up" "us" "we")
  "List of common short English words (1-2 letters) not in the dictionary.")

(defun mozc-modeless--normalize-word (word)
  "Remove trailing punctuation from WORD for dictionary lookup."
  (replace-regexp-in-string "[.,?!;:]+$" "" word))

(defun mozc-modeless--english-text-p (text)
  "Return non-nil if TEXT appears to be English text.
Splits TEXT by whitespace, checks each word against the English
dictionary and short word list.  If the ratio of English words
is >= `mozc-modeless-ambient-english-threshold', return non-nil."
  (let* ((words (split-string text "[ \t]+" t))
         (total (length words))
         (english-count 0))
    (when (> total 0)
      (dolist (raw-word words)
        (let ((word (mozc-modeless--normalize-word raw-word)))
          (when (or (mozc-modeless--english-word-p word)
                    (member word mozc-modeless--short-english-words)
                    ;; Capitalized word (likely proper noun)
                    (and (> (length word) 0)
                         (let ((first-char (aref word 0)))
                           (and (>= first-char ?A) (<= first-char ?Z)))))
            (setq english-count (1+ english-count)))))
      (>= (/ (float english-count) total)
          mozc-modeless-ambient-english-threshold))))

(defun mozc-modeless--ambient-excluded-p ()
  "Return non-nil if ambient conversion should be skipped in the current context."
  (or mozc-modeless--active
      (minibufferp)
      (apply #'derived-mode-p mozc-modeless-ambient-exclude-modes)))

(defun mozc-modeless--get-preceding-text-on-line ()
  "Return the text from the beginning of the line to the cursor.
Leading indentation is excluded."
  (save-excursion
    (let ((end (point)))
      (goto-char (line-beginning-position))
      (skip-chars-forward " \t")
      (buffer-substring-no-properties (point) end))))

(defun mozc-modeless--ends-with-particle-p (text)
  "Return the particle string if TEXT ends with a romaji particle, nil otherwise.
Only matches when the particle is preceded by another romaji character
so isolated particles are not triggered."
  (let ((result nil))
    (dolist (particle mozc-modeless-ambient-particles result)
      (when (and (>= (length text) (1+ (length particle)))
                 (string-suffix-p particle text)
                 ;; The character before the particle must be a letter
                 (let ((preceding-char (aref text (- (length text) (length particle) 1))))
                   (or (and (>= preceding-char ?a) (<= preceding-char ?z))
                       (and (>= preceding-char ?A) (<= preceding-char ?Z)))))
        (setq result particle)))))

(defvar mozc-modeless--ambient-in-progress nil
  "Non-nil when ambient conversion is in progress.")

(defun mozc-modeless--check-ambient-trigger ()
  "Check if the last inserted character should trigger ambient conversion.
This function is added to `post-self-insert-hook'."
  (when (and mozc-modeless-ambient-enable
             (not mozc-modeless--active)
             (not mozc-modeless--ambient-in-progress)
             (not (mozc-modeless--ambient-excluded-p)))
    (let ((last-char (char-before)))
      (cond
       ;; Space trigger: check if preceding text ends with a particle
       ((eq last-char ?\s)
        (let* ((text-before-space
                (save-excursion
                  (backward-char 1)
                  (mozc-modeless--get-preceding-text-on-line)))
               (particle (mozc-modeless--ends-with-particle-p text-before-space)))
          (when (and particle
                     (not (mozc-modeless--english-text-p text-before-space)))
            ;; Delete the space we just typed
            (delete-char -1)
            ;; Get romaji info and trigger ambient conversion
            (let ((roman-data (mozc-modeless--get-preceding-roman)))
              (when roman-data
                (mozc-modeless--ambient-convert roman-data nil))))))
       ;; Punctuation trigger
       ((member (char-to-string last-char) mozc-modeless-ambient-punctuation)
        (let ((punct-char last-char))
          ;; Check conditions before deleting punctuation
          (save-excursion
            (backward-char 1)
            (let* ((text-on-line (mozc-modeless--get-preceding-text-on-line))
                   (roman-data (mozc-modeless--get-preceding-roman)))
              (when (and roman-data
                         (not (mozc-modeless--english-text-p text-on-line)))
                ;; Conditions met: delete punctuation and convert
                (forward-char 1)
                (delete-char -1)
                (mozc-modeless--ambient-convert roman-data punct-char))))))))))

(defun mozc-modeless--ambient-convert (romaji-info punct-char)
  "Perform ambient conversion on ROMAJI-INFO with auto-confirm.
ROMAJI-INFO is (START . STRING) from `mozc-modeless--get-preceding-roman'.
PUNCT-CHAR is the punctuation character that triggered conversion, or nil for space trigger."
  (let* ((start (car romaji-info))
         (roman-string (cdr romaji-info))
         (skip-count (1+ (length roman-string))))
    ;; Delete the romaji from the buffer
    (delete-region start (point))
    ;; Set flag to prevent re-triggering
    (setq mozc-modeless--ambient-in-progress t)
    ;; Activate mozc input method
    (unless current-input-method
      (activate-input-method "japanese-mozc"))
    ;; Set up hook to detect conversion completion and clean up
    (let ((cleanup-count skip-count))
      (letrec ((ambient-finish
                (lambda ()
                  (if (> cleanup-count 0)
                      (setq cleanup-count (1- cleanup-count))
                    (unless (mozc-modeless--preedit-active-p)
                      (mozc-modeless--deactivate-ime)
                      ;; Insert punctuation if this was a punctuation trigger
                      (when punct-char
                        (insert (mozc-modeless--to-fullwidth-punctuation punct-char)))
                      (setq mozc-modeless--ambient-in-progress nil)
                      (remove-hook 'post-command-hook ambient-finish t))))))
        (add-hook 'post-command-hook ambient-finish nil t)))
    ;; Send romaji + space (to trigger conversion) + Enter (to confirm first candidate)
    (mozc-modeless--insert-string (concat roman-string " \r"))))

(defun mozc-modeless--to-fullwidth-punctuation (char)
  "Convert ASCII punctuation CHAR to its fullwidth Japanese equivalent."
  (pcase char
    (?. "。")
    (?, "、")
    (?? "？")
    (_ (char-to-string char))))

;;; Minor mode definition

(defvar mozc-modeless-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map mozc-modeless-convert-key 'mozc-modeless-convert)
    map)
  "Keymap for `mozc-modeless-mode'.")

(defvar mozc-modeless--original-mozc-keymap-entry nil
  "Original binding in mozc-mode-map for `mozc-modeless-convert-key', saved for restoration.")

(defun mozc-modeless--setup-mozc-keymap ()
  "Set up binding in mozc-mode-map for next candidate selection."
  (when (boundp 'mozc-mode-map)
    ;; Save original binding
    (setq mozc-modeless--original-mozc-keymap-entry
          (lookup-key mozc-mode-map mozc-modeless-convert-key))
    ;; Set our binding
    (define-key mozc-mode-map mozc-modeless-convert-key 'mozc-modeless-convert)))

(defun mozc-modeless--restore-mozc-keymap ()
  "Restore original binding for `mozc-modeless-convert-key' in mozc-mode-map."
  (when (boundp 'mozc-mode-map)
    (if mozc-modeless--original-mozc-keymap-entry
        (define-key mozc-mode-map mozc-modeless-convert-key mozc-modeless--original-mozc-keymap-entry)
      (define-key mozc-mode-map mozc-modeless-convert-key nil))))

;;;###autoload
(define-minor-mode mozc-modeless-mode
  "Toggle modeless Japanese input with Mozc.

When enabled, you can type in alphanumeric mode normally. Press \\[mozc-modeless-convert]
to convert the preceding romaji string to Japanese. After conversion is confirmed,
the mode automatically returns to alphanumeric input.

Key bindings:
\\{mozc-modeless-mode-map}"
  :lighter " Mozc-ML"
  :keymap mozc-modeless-mode-map
  :group 'mozc-modeless
  (if mozc-modeless-mode
      (progn
        ;; Enable mode
        (unless (fboundp 'mozc-mode)
          (error "Mozc is not available. Please install mozc.el"))
        ;; Set up convert key in mozc-mode-map
        (mozc-modeless--setup-mozc-keymap)
        ;; Set up ambient conversion hook
        (add-hook 'post-self-insert-hook #'mozc-modeless--check-ambient-trigger nil t))
    ;; Disable mode
    (mozc-modeless--restore-mozc-keymap)
    (remove-hook 'post-self-insert-hook #'mozc-modeless--check-ambient-trigger t)
    (when mozc-modeless--active
      (mozc-modeless--finish))))

;;;###autoload
(define-globalized-minor-mode global-mozc-modeless-mode
  mozc-modeless-mode
  (lambda () (mozc-modeless-mode 1))
  :group 'mozc-modeless)

(provide 'mozc-modeless)
;;; mozc-modeless.el ends here
