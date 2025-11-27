;;; mozc-modeless.el --- Modeless Japanese input with Mozc  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author:
;; Keywords: i18n, extentions
;; Version: 0.1.0
;; Package-Requires: ((emacs "24.4") (mozc "0"))

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

(defvar mozc-modeless-skip-chars "a-zA-Z0-9.,@:`\\-+!\\[\\]?;' \t"
  "Characters to be included in the preceding string for conversion.
Same specification as sumibi.el.")

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

(defun mozc-modeless-convert ()
  "Convert the preceding romaji string to Japanese using Mozc.
This function is bound to `mozc-modeless-convert-key' (default: C-j)."
  (interactive)
  (if mozc-modeless--active
      ;; Already in conversion mode, do nothing (let mozc handle it)
      nil
    ;; Start conversion
    (let ((roman-data (mozc-modeless--get-preceding-roman)))
      (if (not roman-data)
          (message "No romaji found before cursor")
        (let ((start (car roman-data))
              (roman-string (cdr roman-data)))
          ;; Save state
          (setq mozc-modeless--active t
                mozc-modeless--start-pos start
                mozc-modeless--original-string roman-string
                ;; Skip checking for a few commands to let mozc initialize
                ;; +1 for the space key that triggers conversion
                mozc-modeless--skip-check-count (1+ (length roman-string)))
          ;; Delete the romaji string
          (delete-region start (point))
          ;; Activate mozc input method
          (unless current-input-method
            (activate-input-method "japanese-mozc"))
          ;; Set up hook to detect conversion completion
          (add-hook 'post-command-hook #'mozc-modeless--check-finish nil t)
          ;; Insert the romaji string through mozc, followed by space to convert
          (mozc-modeless--insert-string (concat roman-string " ")))))))

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
    (when (string= current-input-method "japanese-mozc")
      (deactivate-input-method))
    ;; Clean up state
    (setq mozc-modeless--active nil
          mozc-modeless--start-pos nil
          mozc-modeless--original-string nil
          mozc-modeless--skip-check-count 0)
    ;; Remove hooks
    (remove-hook 'post-command-hook #'mozc-modeless--check-finish t)))

(defun mozc-modeless-cancel ()
  "Cancel the current conversion and restore the original romaji string."
  (interactive)
  (if (not mozc-modeless--active)
      ;; Not in conversion mode, pass through to default C-g behavior
      (keyboard-quit)
    ;; Cancel mozc conversion by deactivating input method
    (when (string= current-input-method "japanese-mozc")
      (deactivate-input-method))
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
    (setq mozc-modeless--active nil
          mozc-modeless--start-pos nil
          mozc-modeless--original-string nil
          mozc-modeless--skip-check-count 0)
    (remove-hook 'post-command-hook #'mozc-modeless--check-finish t)))

(defun mozc-modeless-reset ()
  "Reset mozc-modeless state.
Use this if the mode gets stuck in an inconsistent state."
  (interactive)
  (when (string= current-input-method "japanese-mozc")
    (deactivate-input-method))
  (setq mozc-modeless--active nil
        mozc-modeless--start-pos nil
        mozc-modeless--original-string nil
        mozc-modeless--skip-check-count 0)
  (remove-hook 'post-command-hook #'mozc-modeless--check-finish t)
  (message "mozc-modeless state reset"))

;;; Minor mode definition

(defvar mozc-modeless-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-j") 'mozc-modeless-convert)
    (define-key map (kbd "C-g") 'mozc-modeless-cancel)
    map)
  "Keymap for `mozc-modeless-mode'.")

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
          (error "Mozc is not available. Please install mozc.el")))
    ;; Disable mode
    (when mozc-modeless--active
      (mozc-modeless--finish))))

;;;###autoload
(define-globalized-minor-mode global-mozc-modeless-mode
  mozc-modeless-mode
  (lambda () (mozc-modeless-mode 1))
  :group 'mozc-modeless)

(provide 'mozc-modeless)
;;; mozc-modeless.el ends here
