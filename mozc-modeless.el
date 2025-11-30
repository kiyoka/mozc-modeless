;;; mozc-modeless.el --- Modeless Japanese input with Mozc  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Kiyoka Nishiyama
;; Keywords: i18n, extentions
;; Version: 0.3.0
;; Package-Requires: ((emacs "29.0") (mozc "0"))

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
;;   (mozc-modeless-mode 1)
;;
;; By default, you type in alphanumeric mode. When you want to convert
;; the preceding romaji to Japanese, press C-j. This will activate Mozc
;; conversion mode. After you confirm the conversion, the mode automatically
;; returns to alphanumeric input.

;;; Code:

(require 'mozc)

;;; Customization

(defgroup mozc-modeless nil
  "Modeless Japanese input with Mozc."
  :group 'mozc
  :prefix "mozc-modeless-")

(defcustom mozc-modeless-convert-key (kbd "C-j")
  "Key sequence to trigger conversion."
  :type 'key-sequence
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
    map)
  "Keymap active only during conversion.")

;;; Utility functions

(defun mozc-modeless--get-preceding-roman ()
  "Get the preceding romaji string before the cursor.
Returns a cons cell (START . STRING) where START is the beginning
position of the romaji string, or nil if no romaji is found."
  (save-excursion
    (let ((end (point)))
      ;; Skip backward over characters defined in mozc-modeless-skip-chars
      (skip-chars-backward mozc-modeless-skip-chars)
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
is sent to mozc, and the slash is deleted."
  (interactive)
  (if mozc-modeless--active
      ;; Already in conversion mode, send space to get next candidate
      (setq unread-command-events (cons ?\s unread-command-events))
    ;; Start conversion
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
            (mozc-modeless--insert-string (concat roman-string " "))))))))

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

(defun mozc-modeless-reset ()
  "Reset mozc-modeless state.
Use this if the mode gets stuck in an inconsistent state."
  (interactive)
  (mozc-modeless--deactivate-ime)
  (mozc-modeless--reset-state)
  (message "mozc-modeless state reset"))

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
        (mozc-modeless--setup-mozc-keymap))
    ;; Disable mode
    (mozc-modeless--restore-mozc-keymap)
    (when mozc-modeless--active
      (mozc-modeless--finish))))

;;;###autoload
(define-globalized-minor-mode global-mozc-modeless-mode
  mozc-modeless-mode
  (lambda () (mozc-modeless-mode 1))
  :group 'mozc-modeless)

(provide 'mozc-modeless)
;;; mozc-modeless.el ends here
