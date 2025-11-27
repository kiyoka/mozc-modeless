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

(defcustom mozc-modeless-roman-regexp "[a-zA-Z]+"
  "Regular expression to match romaji characters.
This is used to detect the preceding romaji string before conversion."
  :type 'regexp
  :group 'mozc-modeless)

(defcustom mozc-modeless-convert-key (kbd "C-j")
  "Key sequence to trigger conversion."
  :type 'key-sequence
  :group 'mozc-modeless)

;;; Internal variables

(defvar mozc-modeless--active nil
  "Non-nil when Mozc conversion mode is active.")

(defvar mozc-modeless--start-pos nil
  "Buffer position where the romaji string started.")

(defvar mozc-modeless--original-string nil
  "Original romaji string before conversion.
This is used to restore the text when conversion is cancelled.")

;;; Utility functions

(defun mozc-modeless--get-preceding-roman ()
  "Get the preceding romaji string before the cursor.
Returns a cons cell (START . STRING) where START is the beginning
position of the romaji string, or nil if no romaji is found."
  (save-excursion
    (let ((end (point)))
      (when (and (> end (line-beginning-position))
                 (looking-back mozc-modeless-roman-regexp (line-beginning-position) t))
        (cons (match-beginning 0) (match-string 0))))))

;;; Main functions

(defun mozc-modeless-convert ()
  "Convert the preceding romaji string to Japanese using Mozc.
This function is bound to `mozc-modeless-convert-key' (default: C-j)."
  (interactive)
  (if mozc-modeless--active
      ;; Already in conversion mode, pass through to mozc
      (call-interactively 'mozc-handle-event)
    ;; Start conversion
    (let ((roman-data (mozc-modeless--get-preceding-roman)))
      (if (not roman-data)
          (message "No romaji found before cursor")
        (let ((start (car roman-data))
              (roman-string (cdr roman-data)))
          ;; Save state
          (setq mozc-modeless--active t
                mozc-modeless--start-pos start
                mozc-modeless--original-string roman-string)
          ;; Delete the romaji string
          (delete-region start (point))
          ;; Activate mozc input method
          (unless current-input-method
            (activate-input-method "japanese-mozc"))
          ;; Insert the romaji string through mozc
          (mozc-modeless--insert-string roman-string)
          ;; Set up hooks to detect conversion completion
          (add-hook 'mozc-handle-event-after-insert-hook
                    'mozc-modeless--check-finish nil t))))))

(defun mozc-modeless--insert-string (str)
  "Insert string STR through Mozc input method."
  (dolist (char (string-to-list str))
    (mozc-handle-event (list 'self-insert-command char))))

(defun mozc-modeless--check-finish ()
  "Check if conversion is finished and clean up if necessary."
  (when (and mozc-modeless--active
             (not (mozc-in-conversion-p)))
    (mozc-modeless--finish)))

(defun mozc-modeless--finish ()
  "Finish conversion mode and return to normal mode."
  (when mozc-modeless--active
    ;; Deactivate mozc input method
    (when (string= current-input-method "japanese-mozc")
      (deactivate-input-method))
    ;; Clean up state
    (setq mozc-modeless--active nil
          mozc-modeless--start-pos nil
          mozc-modeless--original-string nil)
    ;; Remove hooks
    (remove-hook 'mozc-handle-event-after-insert-hook
                 'mozc-modeless--check-finish t)))

(defun mozc-modeless-cancel ()
  "Cancel the current conversion and restore the original romaji string."
  (interactive)
  (when mozc-modeless--active
    ;; Cancel mozc conversion
    (when (mozc-in-conversion-p)
      (mozc-cancel))
    ;; Restore original string
    (when (and mozc-modeless--start-pos mozc-modeless--original-string)
      (goto-char mozc-modeless--start-pos)
      (insert mozc-modeless--original-string))
    ;; Clean up
    (mozc-modeless--finish)))

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
          (error "Mozc is not available. Please install mozc.el"))
        (message "mozc-modeless-mode enabled. Press C-j to convert romaji."))
    ;; Disable mode
    (when mozc-modeless--active
      (mozc-modeless--finish))))

(provide 'mozc-modeless)
;;; mozc-modeless.el ends here
