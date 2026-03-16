;;; t-mode.el --- Major mode for editing T files  -*- lexical-binding: t; -*-

;; Author: T Team
;; Keywords: languages, data, science

;;; Commentary:
;; This is a major mode for editing T language source files.
;; T is a reproducibility-first language for data manipulation.

;;; Code:

(defgroup t-mode nil
  "Major mode for editing T code."
  :prefix "t-"
  :group 'languages)

(defvar t-mode-hook nil
  "Hook run when entering `t-mode'.")

(defvar t-mode-map
  (let ((map (make-sparse-keymap)))
    map)
  "Keymap for `t-mode'.")

(defconst t-keywords
  '("if" "else" "import" "function" "pipeline" "intent" "true" "false" "null" "NA" "in"))

(defconst t-builtins
  '("read_csv" "filter" "mutate" "summarize" "select" "arrange" "group_by" "node" "rn" "pyn" "build_pipeline" "print" "mean" "sqrt" "predict" "t_read_pmml"))

(defconst t-font-lock-keywords
  (let* ((keyword-regexp (regexp-opt t-keywords 'words))
         (builtin-regexp (regexp-opt t-builtins 'words)))
    `((,keyword-regexp . font-lock-keyword-face)
      (,builtin-regexp . font-lock-function-name-face)
      ("\\$[a-zA-Z_][a-zA-Z0-9_]*" . font-lock-variable-name-face)
      ("`[^`]*`" . font-lock-variable-name-face)
      ("--.*$" . font-lock-comment-face))))

(defvar t-mode-syntax-table
  (let ((st (make-syntax-table)))
    ;; Comments start with --
    (modify-syntax-entry ?- ". 12b" st)
    (modify-syntax-entry ?\n "> b" st)
    ;; Strings
    (modify-syntax-entry ?\" "\"" st)
    (modify-syntax-entry ?\' "\"" st)
    ;; Punctuation
    (modify-syntax-entry ?_ "w" st)
    (modify-syntax-entry ?\\ "." st)
    st)
  "Syntax table for `t-mode'.")

;;;###autoload
(define-derived-mode t-mode prog-mode "T"
  "Major mode for editing T files."
  :group 't-mode
  :syntax-table t-mode-syntax-table
  (setq font-lock-defaults '((t-font-lock-keywords)))
  (setq-local comment-start "-- ")
  (setq-local comment-end ""))

;;; REPL Support

(require 'comint)

(defcustom t-repl-executable "t"
  "Path to the T REPL executable."
  :type 'string
  :group 't-mode)

(defvar t-repl-buffer-name "*T REPL*")

;;;###autoload
(defun run-t ()
  "Run an inferior T REPL process."
  (interactive)
  (let ((buffer (get-buffer-create t-repl-buffer-name)))
    (unless (comint-check-proc buffer)
      (with-current-buffer buffer
        (comint-mode)
        (setq-local comint-prompt-regexp "^t> ")
        (setq-local comint-use-prompt-regexp t)
        (apply 'make-comint-in-buffer "T REPL" buffer t-repl-executable nil nil)))
    (display-buffer buffer)
    buffer))

(defun t-send-region (start end)
  "Send the current region to the T REPL."
  (interactive "r")
  (let ((proc (get-buffer-process (run-t))))
    (comint-send-region proc start end)
    (comint-send-string proc "\n")))

(defun t-send-buffer ()
  "Send the entire buffer to the T REPL."
  (interactive)
  (t-send-region (point-min) (point-max)))

(defun t-switch-to-repl ()
  "Switch to the T REPL buffer."
  (interactive)
  (pop-to-buffer (run-t)))

;; Keybindings
(define-key t-mode-map (kbd "C-c C-z") 't-switch-to-repl)
(define-key t-mode-map (kbd "C-c C-c") 't-send-buffer)
(define-key t-mode-map (kbd "C-c C-r") 't-send-region)
(define-key t-mode-map (kbd "C-c C-l") 't-send-line)

(defun t-send-line ()
  "Send the current line to the T REPL."
  (interactive)
  (t-send-region (line-beginning-position) (line-end-position)))

(provide 't-mode)

;;; t-mode.el ends here
