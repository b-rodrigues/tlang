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
    (modify-syntax-entry ?$ "w" st)
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

(defvar t-repl-buffer-name "*T REPL*"
  "Name of the T REPL buffer.")

(defvar t-inferior-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map comint-mode-map)
    (define-key map (kbd "TAB") #'completion-at-point)
    map)
  "Keymap for `t-inferior-mode'.")

(define-derived-mode t-inferior-mode comint-mode "T-REPL"
  "Major mode for the T language REPL.
Provides TAB completion by querying the running T process
via its `:complete' command."
  :group 't-mode
  (setq-local comint-prompt-regexp "^T> \\|^\\.\\.  ")
  (setq-local comint-use-prompt-regexp t)
  (setq-local comint-process-echoes nil)
  (add-hook 'completion-at-point-functions #'t-completion-at-point nil t))

;;;###autoload
(defun run-t ()
  "Run an inferior T REPL process.
If a T REPL is already running, just display its buffer."
  (interactive)
  (let ((buffer (get-buffer-create t-repl-buffer-name)))
    (unless (comint-check-proc buffer)
      (make-comint-in-buffer "T REPL" buffer t-repl-executable nil "repl")
      (with-current-buffer buffer
        (t-inferior-mode)))
    (pop-to-buffer buffer)
    buffer))

(defun t-completion-at-point ()
  "Completion-at-point function for the T REPL.
Sends `:complete <input>' to the T process and returns the
matches for use by `completion-at-point'."
  (let ((proc (get-buffer-process (current-buffer))))
    (when (and proc (process-live-p proc))
      (let* ((pmark (process-mark proc))
             (input-start (marker-position pmark))
             (end (point))
             (input (buffer-substring-no-properties input-start end))
             ;; Find the start of the identifier being completed
             (start (save-excursion
                      (skip-chars-backward "a-zA-Z0-9_")
                      (max (point) input-start))))
        (when (> (length input) 0)
          (let ((completions (t--get-completions input proc)))
            (when completions
              (list start end completions))))))))

(defun t--get-completions (input proc)
  "Query the T REPL process PROC for completions of INPUT.
Sends `:complete INPUT' and parses the output lines."
  (let ((output-buf (get-buffer-create " *t-completions*"))
        (completions nil))
    (with-current-buffer output-buf
      (erase-buffer))
    (let ((comint-redirect-finished-regexp ":END_COMPLETIONS:"))
      (comint-redirect-send-command-to-process
       (concat ":complete " input)
       output-buf proc nil t))
    ;; Wait for the redirect to complete before parsing (with a 2-second timeout)
    (with-current-buffer (process-buffer proc)
      (let ((timeout 2.0)
            (start-time (float-time)))
        (while (and (not comint-redirect-completed)
                    (< (- (float-time) start-time) timeout))
          (accept-process-output proc 0.1))))
    (with-current-buffer output-buf
      (goto-char (point-min))
      (when (search-forward ":BEGIN_COMPLETIONS:" nil t)
        (let ((begin (point)))
          (when (search-forward ":END_COMPLETIONS:" nil t)
            (let ((text (buffer-substring-no-properties begin (match-beginning 0))))
              (setq completions (split-string (string-trim text) "\n" t)))))))
    completions))

(defun t-send-region (start end)
  "Send the current region to the T REPL."
  (interactive "r")
  (let* ((buffer (run-t))
         (proc (get-buffer-process buffer))
         (text (buffer-substring-no-properties start end)))
    (with-current-buffer buffer
      (goto-char (process-mark proc))
      (insert text)
      (comint-send-input))))

(defun t-send-buffer ()
  "Send the entire buffer to the T REPL."
  (interactive)
  (t-send-region (point-min) (point-max)))

(defun t-send-line ()
  "Send the current line to the T REPL."
  (interactive)
  (t-send-region (line-beginning-position) (line-end-position)))

(defun t-switch-to-repl ()
  "Switch to the T REPL buffer."
  (interactive)
  (pop-to-buffer (run-t)))

;; Keybindings for t-mode (editing .t files)
(define-key t-mode-map (kbd "C-c C-z") #'t-switch-to-repl)
(define-key t-mode-map (kbd "C-c C-c") #'t-send-buffer)
(define-key t-mode-map (kbd "C-c C-r") #'t-send-region)
(define-key t-mode-map (kbd "C-c C-l") #'t-send-line)

(provide 't-mode)

;;; t-mode.el ends here
