;;; git.el --- A user interface for git

;; Copyright (C) 2005, 2006, 2007, 2008, 2009 Alexandre Julliard <julliard@winehq.org>

;; Version: 1.0

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied
;; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
;; PURPOSE.  See the GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public
;; License along with this program; if not, write to the Free
;; Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
;; MA 02111-1307 USA

;;; Commentary:

;; This file contains an interface for the git version control
;; system. It provides easy access to the most frequently used git
;; commands. The user interface is as far as possible identical to
;; that of the PCL-CVS mode.
;;
;; To install: put this file on the load-path and place the following
;; in your .emacs file:
;;
;;    (require 'git)
;;
;; To start: `M-x git-status'
;;
;; TODO
;;  - diff against other branch
;;  - renaming files from the status buffer
;;  - creating tags
;;  - fetch/pull
;;  - revlist browser
;;  - git-show-branch browser
;;

;;; Compatibility:
;;
;; This file works on GNU Emacs 21 or later. It may work on older
;; versions but this is not guaranteed.
;;
;; It may work on XEmacs 21, provided that you first install the ewoc
;; and log-edit packages.
;;

(eval-when-compile (require 'cl))
(require 'ewoc)
(require 'log-edit)
(require 'easymenu)


;;;; Customizations
;;;; ------------------------------------------------------------

(defgroup git nil
  "A user interface for the git versioning system."
  :group 'tools)

(defcustom git-committer-name nil
  "User name to use for commits.
The default is to fall back to the repository config,
then to `add-log-full-name' and then to `user-full-name'."
  :group 'git
  :type '(choice (const :tag "Default" nil)
                 (string :tag "Name")))

(defcustom git-committer-email nil
  "Email address to use for commits.
The default is to fall back to the git repository config,
then to `add-log-mailing-address' and then to `user-mail-address'."
  :group 'git
  :type '(choice (const :tag "Default" nil)
                 (string :tag "Email")))

(defcustom git-commits-coding-system nil
  "Default coding system for the log message of git commits."
  :group 'git
  :type '(choice (const :tag "From repository config" nil)
                 (coding-system)))

(defcustom git-append-signed-off-by nil
  "Whether to append a Signed-off-by line to the commit message before editing."
  :group 'git
  :type 'boolean)

(defcustom git-reuse-status-buffer t
  "Whether `git-status' should try to reuse an existing buffer
if there is already one that displays the same directory."
  :group 'git
  :type 'boolean)

(defcustom git-per-dir-ignore-file ".gitignore"
  "Name of the per-directory ignore file."
  :group 'git
  :type 'string)

(defcustom git-show-uptodate nil
  "Whether to display up-to-date files."
  :group 'git
  :type 'boolean)

(defcustom git-show-ignored nil
  "Whether to display ignored files."
  :group 'git
  :type 'boolean)

(defcustom git-show-unknown t
  "Whether to display unknown files."
  :group 'git
  :type 'boolean)


(defface git-status-face
  '((((class color) (background light)) (:foreground "purple"))
    (((class color) (background dark)) (:foreground "salmon")))
  "Git mode face used to highlight added and modified files."
  :group 'git)

(defface git-unmerged-face
  '((((class color) (background light)) (:foreground "red" :bold t))
    (((class color) (background dark)) (:foreground "red" :bold t)))
  "Git mode face used to highlight unmerged files."
  :group 'git)

(defface git-unknown-face
  '((((class color) (background light)) (:foreground "goldenrod" :bold t))
    (((class color) (background dark)) (:foreground "goldenrod" :bold t)))
  "Git mode face used to highlight unknown files."
  :group 'git)

(defface git-uptodate-face
  '((((class color) (background light)) (:foreground "grey60"))
    (((class color) (background dark)) (:foreground "grey40")))
  "Git mode face used to highlight up-to-date files."
  :group 'git)

(defface git-ignored-face
  '((((class color) (background light)) (:foreground "grey60"))
    (((class color) (background dark)) (:foreground "grey40")))
  "Git mode face used to highlight ignored files."
  :group 'git)

(defface git-mark-face
  '((((class color) (background light)) (:foreground "red" :bold t))
    (((class color) (background dark)) (:foreground "tomato" :bold t)))
  "Git mode face used for the file marks."
  :group 'git)

(defface git-header-face
  '((((class color) (background light)) (:foreground "blue"))
    (((class color) (background dark)) (:foreground "blue")))
  "Git mode face used for commit headers."
  :group 'git)

(defface git-separator-face
  '((((class color) (background light)) (:foreground "brown"))
    (((class color) (background dark)) (:foreground "brown")))
  "Git mode face used for commit separator."
  :group 'git)

(defface git-permission-face
  '((((class color) (background light)) (:foreground "green" :bold t))
    (((class color) (background dark)) (:foreground "green" :bold t)))
  "Git mode face used for permission changes."
  :group 'git)


;;;; Utilities
;;;; ------------------------------------------------------------

(defconst git-log-msg-separator "--- log message follows this line ---")

(defvar git-log-edit-font-lock-keywords
  `(("^\\(Author:\\|Date:\\|Merge:\\|Signed-off-by:\\)\\(.*\\)$"
     (1 font-lock-keyword-face)
     (2 font-lock-function-name-face))
    (,(concat "^\\(" (regexp-quote git-log-msg-separator) "\\)$")
     (1 font-lock-comment-face))))

(defun git-get-env-strings (env)
  "Build a list of NAME=VALUE strings from a list of environment strings."
  (mapcar (lambda (entry) (concat (car entry) "=" (cdr entry))) env))

(defun git-call-process (buffer &rest args)
  "Wrapper for call-process that sets environment strings."
  (apply #'call-process "git" nil buffer nil args))

(defun git-call-process-display-error (&rest args)
  "Wrapper for call-process that displays error messages."
  (let* ((dir default-directory)
         (buffer (get-buffer-create "*Git Command Output*"))
         (ok (with-current-buffer buffer
               (let ((default-directory dir)
                     (buffer-read-only nil))
                 (erase-buffer)
                 (eq 0 (apply #'git-call-process (list buffer t) args))))))
    (unless ok (display-message-or-buffer buffer))
    ok))

(defun git-call-process-string (&rest args)
  "Wrapper for call-process that returns the process output as a string,
or nil if the git command failed."
  (with-temp-buffer
    (and (eq 0 (apply #'git-call-process t args))
         (buffer-string))))

(defun git-call-process-string-display-error (&rest args)
  "Wrapper for call-process that displays error message and returns
the process output as a string, or nil if the git command failed."
  (with-temp-buffer
    (if (eq 0 (apply #'git-call-process (list t t) args))
        (buffer-string)
      (display-message-or-buffer (current-buffer))
      nil)))

(defun git-run-process-region (buffer start end program args)
  "Run a git process with a buffer region as input."
  (let ((output-buffer (current-buffer))
        (dir default-directory))
    (with-current-buffer buffer
      (cd dir)
      (apply #'call-process-region start end program
             nil (list output-buffer t) nil args))))

(defun git-run-command-buffer (buffer-name &rest args)
  "Run a git command, sending the output to a buffer named BUFFER-NAME."
  (let ((dir default-directory)
        (buffer (get-buffer-create buffer-name)))
    (message "Running git %s..." (car args))
    (with-current-buffer buffer
      (let ((default-directory dir)
            (buffer-read-only nil))
        (erase-buffer)
        (apply #'git-call-process buffer args)))
    (message "Running git %s...done" (car args))
    buffer))

(defun git-run-command-region (buffer start end env &rest args)
  "Run a git command with specified buffer region as input."
  (with-temp-buffer
    (if (eq 0 (if env
                  (git-run-process-region
                   buffer start end "env"
                   (append (git-get-env-strings env) (list "git") args))
                (git-run-process-region buffer start end "git" args)))
        (buffer-string)
      (display-message-or-buffer (current-buffer))
      nil)))

(defun git-run-hook (hook env &rest args)
  "Run a git hook and display its output if any."
  (let ((dir default-directory)
        (hook-name (expand-file-name (concat ".git/hooks/" hook))))
    (or (not (file-executable-p hook-name))
        (let (status (buffer (get-buffer-create "*Git Hook Output*")))
          (with-current-buffer buffer
            (erase-buffer)
            (cd dir)
            (setq status
                  (if env
                      (apply #'call-process "env" nil (list buffer t) nil
                             (append (git-get-env-strings env) (list hook-name) args))
                    (apply #'call-process hook-name nil (list buffer t) nil args))))
          (display-message-or-buffer buffer)
          (eq 0 status)))))

(defun git-get-string-sha1 (string)
  "Read a SHA1 from the specified string."
  (and string
       (string-match "[0-9a-f]\\{40\\}" string)
       (match-string 0 string)))

(defun git-get-committer-name ()
  "Return the name to use as GIT_COMMITTER_NAME."
  ; copied from log-edit
  (or git-committer-name
      (git-config "user.name")
      (and (boundp 'add-log-full-name) add-log-full-name)
      (and (fboundp 'user-full-name) (user-full-name))
      (and (boundp 'user-full-name) user-full-name)))

(defun git-get-committer-email ()
  "Return the email address to use as GIT_COMMITTER_EMAIL."
  ; copied from log-edit
  (or git-committer-email
      (git-config "user.email")
      (and (boundp 'add-log-mailing-address) add-log-mailing-address)
      (and (fboundp 'user-mail-address) (user-mail-address))
      (and (boundp 'user-mail-address) user-mail-address)))

(defun git-get-commits-coding-system ()
  "Return the coding system to use for commits."
  (let ((repo-config (git-config "i18n.commitencoding")))
    (or git-commits-coding-system
        (and repo-config
             (fboundp 'locale-charset-to-coding-system)
             (locale-charset-to-coding-system repo-config))
      'utf-8)))

(defun git-get-logoutput-coding-system ()
  "Return the coding system used for git-log output."
  (let ((repo-config (or (git-config "i18n.logoutputencoding")
                         (git-config "i18n.commitencoding"))))
    (or git-commits-coding-system
        (and repo-config
             (fboundp 'locale-charset-to-coding-system)
             (locale-charset-to-coding-system repo-config))
      'utf-8)))

(defun git-escape-file-name (name)
  "Escape a file name if necessary."
  (if (string-match "[\n\t\"\\]" name)
      (concat "\""
              (mapconcat (lambda (c)
                   (case c
                     (?\n "\\n")
                     (?\t "\\t")
                     (?\\ "\\\\")
                     (?\" "\\\"")
                     (t (char-to-string c))))
                 name "")
              "\"")
    name))

(defun git-success-message (text files)
  "Print a success message after having handled FILES."
  (let ((n (length files)))
    (if (equal n 1)
        (message "%s %s" text (car files))
      (message "%s %d files" text n))))

(defun git-get-top-dir (dir)
  "Retrieve the top-level directory of a git tree."
  (let ((cdup (with-output-to-string
                (with-current-buffer standard-output
                  (cd dir)
                  (unless (eq 0 (git-call-process t "rev-parse" "--show-cdup"))
                    (error "cannot find top-level git tree for %s." dir))))))
    (expand-file-name (concat (file-name-as-directory dir)
                              (car (split-string cdup "\n"))))))

;stolen from pcl-cvs
(defun git-append-to-ignore (file)
  "Add a file name to the ignore file in its directory."
  (let* ((fullname (expand-file-name file))
         (dir (file-name-directory fullname))
         (name (file-name-nondirectory fullname))
         (ignore-name (expand-file-name git-per-dir-ignore-file dir))
         (created (not (file-exists-p ignore-name))))
  (save-window-excursion
    (set-buffer (find-file-noselect ignore-name))
    (goto-char (point-max))
    (unless (zerop (current-column)) (insert "\n"))
    (insert "/" name "\n")
    (sort-lines nil (point-min) (point-max))
    (save-buffer))
  (when created
    (git-call-process nil "update-index" "--add" "--" (file-relative-name ignore-name)))
  (git-update-status-files (list (file-relative-name ignore-name)))))

; propertize definition for XEmacs, stolen from erc-compat
(eval-when-compile
  (unless (fboundp 'propertize)
    (defun propertize (string &rest props)
      (let ((string (copy-sequence string)))
        (while props
          (put-text-property 0 (length string) (nth 0 props) (nth 1 props) string)
          (setq props (cddr props)))
        string))))

;;;; Wrappers for basic git commands
;;;; ------------------------------------------------------------

(defun git-rev-parse (rev)
  "Parse a revision name and return its SHA1."
  (git-get-string-sha1
   (git-call-process-string "rev-parse" rev)))

(defun git-config (key)
  "Retrieve the value associated to KEY in the git repository config file."
  (let ((str (git-call-process-string "config" key)))
    (and str (car (split-string str "\n")))))

(defun git-symbolic-ref (ref)
  "Wrapper for the git-symbolic-ref command."
  (let ((str (git-call-process-string "symbolic-ref" ref)))
    (and str (car (split-string str "\n")))))

(defun git-update-ref (ref newval &optional oldval reason)
  "Update a reference by calling git-update-ref."
  (let ((args (and oldval (list oldval))))
    (when newval (push newval args))
    (push ref args)
    (when reason
     (push reason args)
     (push "-m" args))
    (unless newval (push "-d" args))
    (apply 'git-call-process-display-error "update-ref" args)))

(defun git-for-each-ref (&rest specs)
  "Return a list of refs using git-for-each-ref.
Each entry is a cons of (SHORT-NAME . FULL-NAME)."
  (let (refs)
    (with-temp-buffer
      (apply #'git-call-process t "for-each-ref" "--format=%(refname)" specs)
      (goto-char (point-min))
      (while (re-search-forward "^[^/\n]+/[^/\n]+/\\(.+\\)$" nil t)
	(push (cons (match-string 1) (match-string 0)) refs)))
    (nreverse refs)))

(defun git-read-tree (tree &optional index-file)
  "Read a tree into the index file."
  (let ((process-environment
         (append (and index-file (list (concat "GIT_INDEX_FILE=" index-file))) process-environment)))
    (apply 'git-call-process-display-error "read-tree" (if tree (list tree)))))

(defun git-write-tree (&optional index-file)
  "Call git-write-tree and return the resulting tree SHA1 as a string."
  (let ((process-environment
         (append (and index-file (list (concat "GIT_INDEX_FILE=" index-file))) process-environment)))
    (git-get-string-sha1
     (git-call-process-string-display-error "write-tree"))))

(defun git-commit-tree (buffer tree parent)
  "Create a commit and possibly update HEAD.
Create a commit with the message in BUFFER using the tree with hash TREE.
Use PARENT as the parent of the new commit. If PARENT is the current \"HEAD\",
update the \"HEAD\" reference to the new commit."
  (let ((author-name (git-get-committer-name))
        (author-email (git-get-committer-email))
        (subject "commit (initial): ")
        author-date log-start log-end args coding-system-for-write)
    (when parent
      (setq subject "commit: ")
      (push "-p" args)
      (push parent args))
    (with-current-buffer buffer
      (goto-char (point-min))
      (if
          (setq log-start (re-search-forward (concat "^" (regexp-quote git-log-msg-separator) "\n") nil t))
          (save-restriction
            (narrow-to-region (point-min) log-start)
            (goto-char (point-min))
            (when (re-search-forward "^Author: +\\(.*?\\) *<\\(.*\\)> *$" nil t)
              (setq author-name (match-string 1)
                    author-email (match-string 2)))
            (goto-char (point-min))
            (when (re-search-forward "^Date: +\\(.*\\)$" nil t)
              (setq author-date (match-string 1)))
            (goto-char (point-min))
            (when (re-search-forward "^Merge: +\\(.*\\)" nil t)
              (setq subject "commit (merge): ")
              (dolist (parent (split-string (match-string 1) " +" t))
                (push "-p" args)
                (push parent args))))
        (setq log-start (point-min)))
      (setq log-end (point-max))
      (goto-char log-start)
      (when (re-search-forward ".*$" nil t)
        (setq subject (concat subject (match-string 0))))
      (setq coding-system-for-write buffer-file-coding-system))
    (let ((commit
           (git-get-string-sha1
            (let ((env `(("GIT_AUTHOR_NAME" . ,author-name)
                         ("GIT_AUTHOR_EMAIL" . ,author-email)
                         ("GIT_COMMITTER_NAME" . ,(git-get-committer-name))
                         ("GIT_COMMITTER_EMAIL" . ,(git-get-committer-email)))))
              (when author-date (push `("GIT_AUTHOR_DATE" . ,author-date) env))
              (apply #'git-run-command-region
                     buffer log-start log-end env
                     "commit-tree" tree (nreverse args))))))
      (when commit (git-update-ref "HEAD" commit parent subject))
      commit)))

(defun git-empty-db-p ()
  "Check if the git db is empty (no commit done yet)."
  (not (eq 0 (git-call-process nil "rev-parse" "--verify" "HEAD"))))

(defun git-get-merge-heads ()
  "Retrieve the merge heads from the MERGE_HEAD file if present."
  (let (heads)
    (when (file-readable-p ".git/MERGE_HEAD")
      (with-temp-buffer
        (insert-file-contents ".git/MERGE_HEAD" nil nil nil t)
        (goto-char (point-min))
        (while (re-search-forward "[0-9a-f]\\{40\\}" nil t)
          (push (match-string 0) heads))))
    (nreverse heads)))

(defun git-get-commit-description (commit)
  "Get a one-line description of COMMIT."
  (let ((coding-system-for-read (git-get-logoutput-coding-system)))
    (let ((descr (git-call-process-string "log" "--max-count=1" "--pretty=oneline" commit)))
      (if (and descr (string-match "\\`\\([0-9a-f]\\{40\\}\\) *\\(.*\\)$" descr))
          (concat (substring (match-string 1 descr) 0 10) " - " (match-string 2 descr))
        descr))))

;;;; File info structure
;;;; ------------------------------------------------------------

; fileinfo structure stolen from pcl-cvs
(defstruct (git-fileinfo
            (:copier nil)
            (:constructor git-create-fileinfo (state name &optional old-perm new-perm rename-state orig-name marked))
            (:conc-name git-fileinfo->))
  marked              ;; t/nil
  state               ;; current state
  name                ;; file name
  old-perm new-perm   ;; permission flags
  rename-state        ;; rename or copy state
  orig-name           ;; original name for renames or copies
  needs-update        ;; whether file needs to be updated
  needs-refresh)      ;; whether file needs to be refreshed

(defvar git-status nil)

(defun git-set-fileinfo-state (info state)
  "Set the state of a file info."
  (unless (eq (git-fileinfo->state info) state)
    (setf (git-fileinfo->state info) state
	  (git-fileinfo->new-perm info) (git-fileinfo->old-perm info)
          (git-fileinfo->rename-state info) nil
          (git-fileinfo->orig-name info) nil
          (git-fileinfo->needs-update info) nil
          (git-fileinfo->needs-refresh info) t)))

(defun git-status-filenames-map (status func files &rest args)
  "Apply FUNC to the status files names in the FILES list.
The list must be sorted."
  (when files
    (let ((file (pop files))
          (node (ewoc-nth status 0)))
      (while (and file node)
        (let* ((info (ewoc-data node))
               (name (git-fileinfo->name info)))
          (if (string-lessp name file)
              (setq node (ewoc-next status node))
            (if (string-equal name file)
                (apply func info args))
            (setq file (pop files))))))))

(defun git-set-filenames-state (status files state)
  "Set the state of a list of named files. The list must be sorted"
  (when files
    (git-status-filenames-map status #'git-set-fileinfo-state files state)
    (unless state  ;; delete files whose state has been set to nil
      (ewoc-filter status (lambda (info) (git-fileinfo->state info))))))

(defun git-state-code (code)
  "Convert from a string to a added/deleted/modified state."
  (case (string-to-char code)
    (?M 'modified)
    (?? 'unknown)
    (?A 'added)
    (?D 'deleted)
    (?U 'unmerged)
    (?T 'modified)
    (t nil)))

(defun git-status-code-as-string (code)
  "Format a git status code as string."
  (case code
    ('modified (propertize "Modified" 'face 'git-status-face))
    ('unknown  (propertize "Unknown " 'face 'git-unknown-face))
    ('added    (propertize "Added   " 'face 'git-status-face))
    ('deleted  (propertize "Deleted " 'face 'git-status-face))
    ('unmerged (propertize "Unmerged" 'face 'git-unmerged-face))
    ('uptodate (propertize "Uptodate" 'face 'git-uptodate-face))
    ('ignored  (propertize "Ignored " 'face 'git-ignored-face))
    (t "?       ")))

(defun git-file-type-as-string (old-perm new-perm)
  "Return a string describing the file type based on its permissions."
  (let* ((old-type (lsh (or old-perm 0) -9))
	 (new-type (lsh (or new-perm 0) -9))
	 (str (case new-type
		(64  ;; file
		 (case old-type
		   (64 nil)
		   (80 "   (type change symlink -> file)")
		   (112 "   (type change subproject -> file)")))
		 (80  ;; symlink
		  (case old-type
		    (64 "   (type change file -> symlink)")
		    (112 "   (type change subproject -> symlink)")
		    (t "   (symlink)")))
		  (112  ;; subproject
		   (case old-type
		     (64 "   (type change file -> subproject)")
		     (80 "   (type change symlink -> subproject)")
		     (t "   (subproject)")))
                  (72 nil)  ;; directory (internal, not a real git state)
		  (0  ;; deleted or unknown
		   (case old-type
		     (80 "   (symlink)")
		     (112 "   (subproject)")))
		  (t (format "   (unknown type %o)" new-type)))))
    (cond (str (propertize str 'face 'git-status-face))
          ((eq new-type 72) "/")
          (t ""))))

(defun git-rename-as-string (info)
  "Return a string describing the copy or rename associated with INFO, or an empty string if none."
  (let ((state (git-fileinfo->rename-state info)))
    (if state
        (propertize
         (concat "   ("
                 (if (eq state 'copy) "copied from "
                   (if (eq (git-fileinfo->state info) 'added) "renamed from "
                     "renamed to "))
                 (git-escape-file-name (git-fileinfo->orig-name info))
                 ")") 'face 'git-status-face)
      "")))

(defun git-permissions-as-string (old-perm new-perm)
  "Format a permission change as string."
  (propertize
   (if (or (not old-perm)
           (not new-perm)
           (eq 0 (logand ?\111 (logxor old-perm new-perm))))
       "  "
     (if (eq 0 (logand ?\111 old-perm)) "+x" "-x"))
  'face 'git-permission-face))

(defun git-fileinfo-prettyprint (info)
  "Pretty-printer for the git-fileinfo structure."
  (let ((old-perm (git-fileinfo->old-perm info))
	(new-perm (git-fileinfo->new-perm info)))
    (insert (concat "   " (if (git-fileinfo->marked info) (propertize "*" 'face 'git-mark-face) " ")
		    " " (git-status-code-as-string (git-fileinfo->state info))
		    " " (git-permissions-as-string old-perm new-perm)
		    "  " (git-escape-file-name (git-fileinfo->name info))
		    (git-file-type-as-string old-perm new-perm)
		    (git-rename-as-string info)))))

(defun git-update-node-fileinfo (node info)
  "Update the fileinfo of the specified node. The names are assumed to match already."
  (let ((data (ewoc-data node)))
    (setf
     ;; preserve the marked flag
     (git-fileinfo->marked info) (git-fileinfo->marked data)
     (git-fileinfo->needs-update data) nil)
    (when (not (equal info data))
      (setf (git-fileinfo->needs-refresh info) t
            (ewoc-data node) info))))

(defun git-insert-info-list (status infolist files)
  "Insert a sorted list of file infos in the status buffer, replacing existing ones if any."
  (let* ((info (pop infolist))
         (node (ewoc-nth status 0))
         (name (and info (git-fileinfo->name info)))
         remaining)
    (while info
      (let ((nodename (and node (git-fileinfo->name (ewoc-data node)))))
        (while (and files (string-lessp (car files) name))
          (push (pop files) remaining))
        (when (and files (string-equal (car files) name))
          (setq files (cdr files)))
        (cond ((not nodename)
               (setq node (ewoc-enter-last status info))
               (setq info (pop infolist))
               (setq name (and info (git-fileinfo->name info))))
              ((string-lessp nodename name)
               (setq node (ewoc-next status node)))
              ((string-equal nodename name)
               ;; preserve the marked flag
               (git-update-node-fileinfo node info)
               (setq info (pop infolist))
               (setq name (and info (git-fileinfo->name info))))
              (t
               (setq node (ewoc-enter-before status node info))
               (setq info (pop infolist))
               (setq name (and info (git-fileinfo->name info)))))))
    (nconc (nreverse remaining) files)))

(defun git-run-diff-index (status files)
  "Run git-diff-index on FILES and parse the results into STATUS.
Return the list of files that haven't been handled."
  (let (infolist)
    (with-temp-buffer
      (apply #'git-call-process t "diff-index" "-z" "-M" "HEAD" "--" files)
      (goto-char (point-min))
      (while (re-search-forward
	      ":\\([0-7]\\{6\\}\\) \\([0-7]\\{6\\}\\) [0-9a-f]\\{40\\} [0-9a-f]\\{40\\} \\(\\([ADMUT]\\)\0\\([^\0]+\\)\\|\\([CR]\\)[0-9]*\0\\([^\0]+\\)\0\\([^\0]+\\)\\)\0"
              nil t 1)
        (let ((old-perm (string-to-number (match-string 1) 8))
              (new-perm (string-to-number (match-string 2) 8))
              (state (or (match-string 4) (match-string 6)))
              (name (or (match-string 5) (match-string 7)))
              (new-name (match-string 8)))
          (if new-name  ; copy or rename
              (if (eq ?C (string-to-char state))
                  (push (git-create-fileinfo 'added new-name old-perm new-perm 'copy name) infolist)
                (push (git-create-fileinfo 'deleted name 0 0 'rename new-name) infolist)
                (push (git-create-fileinfo 'added new-name old-perm new-perm 'rename name) infolist))
            (push (git-create-fileinfo (git-state-code state) name old-perm new-perm) infolist)))))
    (setq infolist (sort (nreverse infolist)
                         (lambda (info1 info2)
                           (string-lessp (git-fileinfo->name info1)
                                         (git-fileinfo->name info2)))))
    (git-insert-info-list status infolist files)))

(defun git-find-status-file (status file)
  "Find a given file in the status ewoc and return its node."
  (let ((node (ewoc-nth status 0)))
    (while (and node (not (string= file (git-fileinfo->name (ewoc-data node)))))
      (setq node (ewoc-next status node)))
    node))

(defun git-run-ls-files (status files default-state &rest options)
  "Run git-ls-files on FILES and parse the results into STATUS.
Return the list of files that haven't been handled."
  (let (infolist)
    (with-temp-buffer
      (apply #'git-call-process t "ls-files" "-z" (append options (list "--") files))
      (goto-char (point-min))
      (while (re-search-forward "\\([^\0]*?\\)\\(/?\\)\0" nil t 1)
        (let ((name (match-string 1)))
          (push (git-create-fileinfo default-state name 0
                                     (if (string-equal "/" (match-string 2)) (lsh ?\110 9) 0))
                infolist))))
    (setq infolist (nreverse infolist))  ;; assume it is sorted already
    (git-insert-info-list status infolist files)))

(defun git-run-ls-files-cached (status files default-state)
  "Run git-ls-files -c on FILES and parse the results into STATUS.
Return the list of files that haven't been handled."
  (let (infolist)
    (with-temp-buffer
      (apply #'git-call-process t "ls-files" "-z" "-s" "-c" "--" files)
      (goto-char (point-min))
      (while (re-search-forward "\\([0-7]\\{6\\}\\) [0-9a-f]\\{40\\} 0\t\\([^\0]+\\)\0" nil t)
	(let* ((new-perm (string-to-number (match-string 1) 8))
	       (old-perm (if (eq default-state 'added) 0 new-perm))
	       (name (match-string 2)))
	  (push (git-create-fileinfo default-state name old-perm new-perm) infolist))))
    (setq infolist (nreverse infolist))  ;; assume it is sorted already
    (git-insert-info-list status infolist files)))

(defun git-run-ls-unmerged (status files)
  "Run git-ls-files -u on FILES and parse the results into STATUS."
  (with-temp-buffer
    (apply #'git-call-process t "ls-files" "-z" "-u" "--" files)
    (goto-char (point-min))
    (let (unmerged-files)
      (while (re-search-forward "[0-7]\\{6\\} [0-9a-f]\\{40\\} [123]\t\\([^\0]+\\)\0" nil t)
        (push (match-string 1) unmerged-files))
      (setq unmerged-files (nreverse unmerged-files))  ;; assume it is sorted already
      (git-set-filenames-state status unmerged-files 'unmerged))))

(defun git-get-exclude-files ()
  "Get the list of exclude files to pass to git-ls-files."
  (let (files
        (config (git-config "core.excludesfile")))
    (when (file-readable-p ".git/info/exclude")
      (push ".git/info/exclude" files))
    (when (and config (file-readable-p config))
      (push config files))
    files))

(defun git-run-ls-files-with-excludes (status files default-state &rest options)
  "Run git-ls-files on FILES with appropriate --exclude-from options."
  (let ((exclude-files (git-get-exclude-files)))
    (apply #'git-run-ls-files status files default-state "--directory" "--no-empty-directory"
           (concat "--exclude-per-directory=" git-per-dir-ignore-file)
           (append options (mapcar (lambda (f) (concat "--exclude-from=" f)) exclude-files)))))

(defun git-update-status-files (&optional files mark-files)
  "Update the status of FILES from the index.
The FILES list must be sorted."
  (unless git-status (error "Not in git-status buffer."))
  ;; set the needs-update flag on existing files
  (if files
      (git-status-filenames-map
       git-status (lambda (info) (setf (git-fileinfo->needs-update info) t)) files)
    (ewoc-map (lambda (info) (setf (git-fileinfo->needs-update info) t) nil) git-status)
    (git-call-process nil "update-index" "--refresh")
    (when git-show-uptodate
      (git-run-ls-files-cached git-status nil 'uptodate)))
  (let ((remaining-files
          (if (git-empty-db-p) ; we need some special handling for an empty db
	      (git-run-ls-files-cached git-status files 'added)
            (git-run-diff-index git-status files))))
    (git-run-ls-unmerged git-status files)
    (when (or remaining-files (and git-show-unknown (not files)))
      (setq remaining-files (git-run-ls-files-with-excludes git-status remaining-files 'unknown "-o")))
    (when (or remaining-files (and git-show-ignored (not files)))
      (setq remaining-files (git-run-ls-files-with-excludes git-status remaining-files 'ignored "-o" "-i")))
    (unless files
      (setq remaining-files (git-get-filenames (ewoc-collect git-status #'git-fileinfo->needs-update))))
    (when remaining-files
      (setq remaining-files (git-run-ls-files-cached git-status remaining-files 'uptodate)))
    (git-set-filenames-state git-status remaining-files nil)
    (when mark-files (git-mark-files git-status files))
    (git-refresh-files)
    (git-refresh-ewoc-hf git-status)))

(defun git-mark-files (status files)
  "Mark all the specified FILES, and unmark the others."
  (let ((file (and files (pop files)))
        (node (ewoc-nth status 0)))
    (while node
      (let ((info (ewoc-data node)))
        (if (and file (string-equal (git-fileinfo->name info) file))
            (progn
              (unless (git-fileinfo->marked info)
                (setf (git-fileinfo->marked info) t)
                (setf (git-fileinfo->needs-refresh info) t))
              (setq file (pop files))
              (setq node (ewoc-next status node)))
          (when (git-fileinfo->marked info)
            (setf (git-fileinfo->marked info) nil)
            (setf (git-fileinfo->needs-refresh info) t))
          (if (and file (string-lessp file (git-fileinfo->name info)))
              (setq file (pop files))
            (setq node (ewoc-next status node))))))))

(defun git-marked-files ()
  "Return a list of all marked files, or if none a list containing just the file at cursor position."
  (unless git-status (error "Not in git-status buffer."))
  (or (ewoc-collect git-status (lambda (info) (git-fileinfo->marked info)))
      (list (ewoc-data (ewoc-locate git-status)))))

(defun git-marked-files-state (&rest states)
  "Return a sorted list of marked files that are in the specified states."
  (let ((files (git-marked-files))
        result)
    (dolist (info files)
      (when (memq (git-fileinfo->state info) states)
        (push info result)))
    (nreverse result)))

(defun git-refresh-files ()
  "Refresh all files that need it and clear the needs-refresh flag."
  (unless git-status (error "Not in git-status buffer."))
  (ewoc-map
   (lambda (info)
     (let ((refresh (git-fileinfo->needs-refresh info)))
       (setf (git-fileinfo->needs-refresh info) nil)
       refresh))
   git-status)
  ; move back to goal column
  (when goal-column (move-to-column goal-column)))

(defun git-refresh-ewoc-hf (status)
  "Refresh the ewoc header and footer."
  (let ((branch (git-symbolic-ref "HEAD"))
        (head (if (git-empty-db-p) "Nothing committed yet"
                (git-get-commit-description "HEAD")))
        (merge-heads (git-get-merge-heads)))
    (ewoc-set-hf status
                 (format "Directory:  %s\nBranch:     %s\nHead:       %s%s\n"
                         default-directory
                         (if branch
                             (if (string-match "^refs/heads/" branch)
                                 (substring branch (match-end 0))
                               branch)
                           "none (detached HEAD)")
                         head
                         (if merge-heads
                             (concat "\nMerging:    "
                                     (mapconcat (lambda (str) (git-get-commit-description str)) merge-heads "\n            "))
                           ""))
                 (if (ewoc-nth status 0) "" "    No changes."))))

(defun git-get-filenames (files)
  (mapcar (lambda (info) (git-fileinfo->name info)) files))

(defun git-update-index (index-file files)
  "Run git-update-index on a list of files."
  (let ((process-environment (append (and index-file (list (concat "GIT_INDEX_FILE=" index-file)))
                                     process-environment))
        added deleted modified)
    (dolist (info files)
      (case (git-fileinfo->state info)
        ('added (push info added))
        ('deleted (push info deleted))
        ('modified (push info modified))))
    (and
     (or (not added) (apply #'git-call-process-display-error "update-index" "--add" "--" (git-get-filenames added)))
     (or (not deleted) (apply #'git-call-process-display-error "update-index" "--remove" "--" (git-get-filenames deleted)))
     (or (not modified) (apply #'git-call-process-display-error "update-index" "--" (git-get-filenames modified))))))

(defun git-run-pre-commit-hook ()
  "Run the pre-commit hook if any."
  (unless git-status (error "Not in git-status buffer."))
  (let ((files (git-marked-files-state 'added 'deleted 'modified)))
    (or (not files)
        (not (file-executable-p ".git/hooks/pre-commit"))
        (let ((index-file (make-temp-file "gitidx")))
          (unwind-protect
            (let ((head-tree (unless (git-empty-db-p) (git-rev-parse "HEAD^{tree}"))))
              (git-read-tree head-tree index-file)
              (git-update-index index-file files)
              (git-run-hook "pre-commit" `(("GIT_INDEX_FILE" . ,index-file))))
          (delete-file index-file))))))

(defun git-do-commit ()
  "Perform the actual commit using the current buffer as log message."
  (interactive)
  (let ((buffer (current-buffer))
        (index-file (make-temp-file "gitidx")))
    (with-current-buffer log-edit-parent-buffer
      (if (git-marked-files-state 'unmerged)
          (message "You cannot commit unmerged files, resolve them first.")
        (unwind-protect
            (let ((files (git-marked-files-state 'added 'deleted 'modified))
                  head tree head-tree)
              (unless (git-empty-db-p)
                (setq head (git-rev-parse "HEAD")
                      head-tree (git-rev-parse "HEAD^{tree}")))
              (message "Running git commit...")
              (when
                  (and
                   (git-read-tree head-tree index-file)
                   (git-update-index nil files)         ;update both the default index
                   (git-update-index index-file files)  ;and the temporary one
                   (setq tree (git-write-tree index-file)))
                (if (or (not (string-equal tree head-tree))
                        (yes-or-no-p "The tree was not modified, do you really want to perform an empty commit? "))
                    (let ((commit (git-commit-tree buffer tree head)))
                      (when commit
                        (condition-case nil (delete-file ".git/MERGE_HEAD") (error nil))
                        (condition-case nil (delete-file ".git/MERGE_MSG") (error nil))
                        (with-current-buffer buffer (erase-buffer))
                        (git-update-status-files (git-get-filenames files))
                        (git-call-process nil "rerere")
                        (git-call-process nil "gc" "--auto")
                        (message "Committed %s." commit)
                        (git-run-hook "post-commit" nil)))
                  (message "Commit aborted."))))
          (delete-file index-file))))))


;;;; Interactive functions
;;;; ------------------------------------------------------------

(defun git-mark-file ()
  "Mark the file that the cursor is on and move to the next one."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let* ((pos (ewoc-locate git-status))
         (info (ewoc-data pos)))
    (setf (git-fileinfo->marked info) t)
    (ewoc-invalidate git-status pos)
    (ewoc-goto-next git-status 1)))

(defun git-unmark-file ()
  "Unmark the file that the cursor is on and move to the next one."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let* ((pos (ewoc-locate git-status))
         (info (ewoc-data pos)))
    (setf (git-fileinfo->marked info) nil)
    (ewoc-invalidate git-status pos)
    (ewoc-goto-next git-status 1)))

(defun git-unmark-file-up ()
  "Unmark the file that the cursor is on and move to the previous one."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let* ((pos (ewoc-locate git-status))
         (info (ewoc-data pos)))
    (setf (git-fileinfo->marked info) nil)
    (ewoc-invalidate git-status pos)
    (ewoc-goto-prev git-status 1)))

(defun git-mark-all ()
  "Mark all files."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (ewoc-map (lambda (info) (unless (git-fileinfo->marked info)
                             (setf (git-fileinfo->marked info) t))) git-status)
  ; move back to goal column after invalidate
  (when goal-column (move-to-column goal-column)))

(defun git-unmark-all ()
  "Unmark all files."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (ewoc-map (lambda (info) (when (git-fileinfo->marked info)
                             (setf (git-fileinfo->marked info) nil)
                             t)) git-status)
  ; move back to goal column after invalidate
  (when goal-column (move-to-column goal-column)))

(defun git-toggle-all-marks ()
  "Toggle all file marks."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (ewoc-map (lambda (info) (setf (git-fileinfo->marked info) (not (git-fileinfo->marked info))) t) git-status)
  ; move back to goal column after invalidate
  (when goal-column (move-to-column goal-column)))

(defun git-next-file (&optional n)
  "Move the selection down N files."
  (interactive "p")
  (unless git-status (error "Not in git-status buffer."))
  (ewoc-goto-next git-status n))

(defun git-prev-file (&optional n)
  "Move the selection up N files."
  (interactive "p")
  (unless git-status (error "Not in git-status buffer."))
  (ewoc-goto-prev git-status n))

(defun git-next-unmerged-file (&optional n)
  "Move the selection down N unmerged files."
  (interactive "p")
  (unless git-status (error "Not in git-status buffer."))
  (let* ((last (ewoc-locate git-status))
         (node (ewoc-next git-status last)))
    (while (and node (> n 0))
      (when (eq 'unmerged (git-fileinfo->state (ewoc-data node)))
        (setq n (1- n))
        (setq last node))
      (setq node (ewoc-next git-status node)))
    (ewoc-goto-node git-status last)))

(defun git-prev-unmerged-file (&optional n)
  "Move the selection up N unmerged files."
  (interactive "p")
  (unless git-status (error "Not in git-status buffer."))
  (let* ((last (ewoc-locate git-status))
         (node (ewoc-prev git-status last)))
    (while (and node (> n 0))
      (when (eq 'unmerged (git-fileinfo->state (ewoc-data node)))
        (setq n (1- n))
        (setq last node))
      (setq node (ewoc-prev git-status node)))
    (ewoc-goto-node git-status last)))

(defun git-insert-file (file)
  "Insert file(s) into the git-status buffer."
  (interactive "fInsert file: ")
  (git-update-status-files (list (file-relative-name file))))

(defun git-add-file ()
  "Add marked file(s) to the index cache."
  (interactive)
  (let ((files (git-get-filenames (git-marked-files-state 'unknown 'ignored 'unmerged))))
    ;; FIXME: add support for directories
    (unless files
      (push (file-relative-name (read-file-name "File to add: " nil nil t)) files))
    (when (apply 'git-call-process-display-error "update-index" "--add" "--" files)
      (git-update-status-files files)
      (git-success-message "Added" files))))

(defun git-ignore-file ()
  "Add marked file(s) to the ignore list."
  (interactive)
  (let ((files (git-get-filenames (git-marked-files-state 'unknown))))
    (unless files
      (push (file-relative-name (read-file-name "File to ignore: " nil nil t)) files))
    (dolist (f files) (git-append-to-ignore f))
    (git-update-status-files files)
    (git-success-message "Ignored" files)))

(defun git-remove-file ()
  "Remove the marked file(s)."
  (interactive)
  (let ((files (git-get-filenames (git-marked-files-state 'added 'modified 'unknown 'uptodate 'ignored))))
    (unless files
      (push (file-relative-name (read-file-name "File to remove: " nil nil t)) files))
    (if (yes-or-no-p
         (if (cdr files)
             (format "Remove %d files? " (length files))
           (format "Remove %s? " (car files))))
        (progn
          (dolist (name files)
            (ignore-errors
              (if (file-directory-p name)
                  (delete-directory name)
                (delete-file name))))
          (when (apply 'git-call-process-display-error "update-index" "--remove" "--" files)
            (git-update-status-files files)
            (git-success-message "Removed" files)))
      (message "Aborting"))))

(defun git-revert-file ()
  "Revert changes to the marked file(s)."
  (interactive)
  (let ((files (git-marked-files-state 'added 'deleted 'modified 'unmerged))
        added modified)
    (when (and files
               (yes-or-no-p
                (if (cdr files)
                    (format "Revert %d files? " (length files))
                  (format "Revert %s? " (git-fileinfo->name (car files))))))
      (dolist (info files)
        (case (git-fileinfo->state info)
          ('added (push (git-fileinfo->name info) added))
          ('deleted (push (git-fileinfo->name info) modified))
          ('unmerged (push (git-fileinfo->name info) modified))
          ('modified (push (git-fileinfo->name info) modified))))
      ;; check if a buffer contains one of the files and isn't saved
      (dolist (file modified)
        (let ((buffer (get-file-buffer file)))
          (when (and buffer (buffer-modified-p buffer))
            (error "Buffer %s is modified. Please kill or save modified buffers before reverting." (buffer-name buffer)))))
      (let ((ok (and
                 (or (not added)
                     (apply 'git-call-process-display-error "update-index" "--force-remove" "--" added))
                 (or (not modified)
                     (apply 'git-call-process-display-error "checkout" "HEAD" modified))))
            (names (git-get-filenames files)))
        (git-update-status-files names)
        (when ok
          (dolist (file modified)
            (let ((buffer (get-file-buffer file)))
              (when buffer (with-current-buffer buffer (revert-buffer t t t)))))
          (git-success-message "Reverted" names))))))

(defun git-remove-handled ()
  "Remove handled files from the status list."
  (interactive)
  (ewoc-filter git-status
               (lambda (info)
                 (case (git-fileinfo->state info)
                   ('ignored git-show-ignored)
                   ('uptodate git-show-uptodate)
                   ('unknown git-show-unknown)
                   (t t))))
  (unless (ewoc-nth git-status 0)  ; refresh header if list is empty
    (git-refresh-ewoc-hf git-status)))

(defun git-toggle-show-uptodate ()
  "Toogle the option for showing up-to-date files."
  (interactive)
  (if (setq git-show-uptodate (not git-show-uptodate))
      (git-refresh-status)
    (git-remove-handled)))

(defun git-toggle-show-ignored ()
  "Toogle the option for showing ignored files."
  (interactive)
  (if (setq git-show-ignored (not git-show-ignored))
      (progn
        (message "Inserting ignored files...")
        (git-run-ls-files-with-excludes git-status nil 'ignored "-o" "-i")
        (git-refresh-files)
        (git-refresh-ewoc-hf git-status)
        (message "Inserting ignored files...done"))
    (git-remove-handled)))

(defun git-toggle-show-unknown ()
  "Toogle the option for showing unknown files."
  (interactive)
  (if (setq git-show-unknown (not git-show-unknown))
      (progn
        (message "Inserting unknown files...")
        (git-run-ls-files-with-excludes git-status nil 'unknown "-o")
        (git-refresh-files)
        (git-refresh-ewoc-hf git-status)
        (message "Inserting unknown files...done"))
    (git-remove-handled)))

(defun git-expand-directory (info)
  "Expand the directory represented by INFO to list its files."
  (when (eq (lsh (git-fileinfo->new-perm info) -9) ?\110)
    (let ((dir (git-fileinfo->name info)))
      (git-set-filenames-state git-status (list dir) nil)
      (git-run-ls-files-with-excludes git-status (list (concat dir "/")) 'unknown "-o")
      (git-refresh-files)
      (git-refresh-ewoc-hf git-status)
      t)))

(defun git-setup-diff-buffer (buffer)
  "Setup a buffer for displaying a diff."
  (let ((dir default-directory))
    (with-current-buffer buffer
      (diff-mode)
      (goto-char (point-min))
      (setq default-directory dir)
      (setq buffer-read-only t)))
  (display-buffer buffer)
  ; shrink window only if it displays the status buffer
  (when (eq (window-buffer) (current-buffer))
    (shrink-window-if-larger-than-buffer)))

(defun git-diff-file ()
  "Diff the marked file(s) against HEAD."
  (interactive)
  (let ((files (git-marked-files)))
    (git-setup-diff-buffer
     (apply #'git-run-command-buffer "*git-diff*" "diff-index" "-p" "-M" "HEAD" "--" (git-get-filenames files)))))

(defun git-diff-file-merge-head (arg)
  "Diff the marked file(s) against the first merge head (or the nth one with a numeric prefix)."
  (interactive "p")
  (let ((files (git-marked-files))
        (merge-heads (git-get-merge-heads)))
    (unless merge-heads (error "No merge in progress"))
    (git-setup-diff-buffer
     (apply #'git-run-command-buffer "*git-diff*" "diff-index" "-p" "-M"
            (or (nth (1- arg) merge-heads) "HEAD") "--" (git-get-filenames files)))))

(defun git-diff-unmerged-file (stage)
  "Diff the marked unmerged file(s) against the specified stage."
  (let ((files (git-marked-files)))
    (git-setup-diff-buffer
     (apply #'git-run-command-buffer "*git-diff*" "diff-files" "-p" stage "--" (git-get-filenames files)))))

(defun git-diff-file-base ()
  "Diff the marked unmerged file(s) against the common base file."
  (interactive)
  (git-diff-unmerged-file "-1"))

(defun git-diff-file-mine ()
  "Diff the marked unmerged file(s) against my pre-merge version."
  (interactive)
  (git-diff-unmerged-file "-2"))

(defun git-diff-file-other ()
  "Diff the marked unmerged file(s) against the other's pre-merge version."
  (interactive)
  (git-diff-unmerged-file "-3"))

(defun git-diff-file-combined ()
  "Do a combined diff of the marked unmerged file(s)."
  (interactive)
  (git-diff-unmerged-file "-c"))

(defun git-diff-file-idiff ()
  "Perform an interactive diff on the current file."
  (interactive)
  (let ((files (git-marked-files-state 'added 'deleted 'modified)))
    (unless (eq 1 (length files))
      (error "Cannot perform an interactive diff on multiple files."))
    (let* ((filename (car (git-get-filenames files)))
           (buff1 (find-file-noselect filename))
           (buff2 (git-run-command-buffer (concat filename ".~HEAD~") "cat-file" "blob" (concat "HEAD:" filename))))
      (ediff-buffers buff1 buff2))))

(defun git-log-file ()
  "Display a log of changes to the marked file(s)."
  (interactive)
  (let* ((files (git-marked-files))
         (coding-system-for-read git-commits-coding-system)
         (buffer (apply #'git-run-command-buffer "*git-log*" "rev-list" "--pretty" "HEAD" "--" (git-get-filenames files))))
    (with-current-buffer buffer
      ; (git-log-mode)  FIXME: implement log mode
      (goto-char (point-min))
      (setq buffer-read-only t))
    (display-buffer buffer)))

(defun git-log-edit-files ()
  "Return a list of marked files for use in the log-edit buffer."
  (with-current-buffer log-edit-parent-buffer
    (git-get-filenames (git-marked-files-state 'added 'deleted 'modified))))

(defun git-log-edit-diff ()
  "Run a diff of the current files being committed from a log-edit buffer."
  (with-current-buffer log-edit-parent-buffer
    (git-diff-file)))

(defun git-append-sign-off (name email)
  "Append a Signed-off-by entry to the current buffer, avoiding duplicates."
  (let ((sign-off (format "Signed-off-by: %s <%s>" name email))
        (case-fold-search t))
    (goto-char (point-min))
    (unless (re-search-forward (concat "^" (regexp-quote sign-off)) nil t)
      (goto-char (point-min))
      (unless (re-search-forward "^Signed-off-by: " nil t)
        (setq sign-off (concat "\n" sign-off)))
      (goto-char (point-max))
      (insert sign-off "\n"))))

(defun git-setup-log-buffer (buffer &optional merge-heads author-name author-email subject date msg)
  "Setup the log buffer for a commit."
  (unless git-status (error "Not in git-status buffer."))
  (let ((dir default-directory)
        (committer-name (git-get-committer-name))
        (committer-email (git-get-committer-email))
        (sign-off git-append-signed-off-by))
    (with-current-buffer buffer
      (cd dir)
      (erase-buffer)
      (insert
       (propertize
        (format "Author: %s <%s>\n%s%s"
                (or author-name committer-name)
                (or author-email committer-email)
                (if date (format "Date: %s\n" date) "")
                (if merge-heads
                    (format "Merge: %s\n"
                            (mapconcat 'identity merge-heads " "))
                  ""))
        'face 'git-header-face)
       (propertize git-log-msg-separator 'face 'git-separator-face)
       "\n")
      (when subject (insert subject "\n\n"))
      (cond (msg (insert msg "\n"))
            ((file-readable-p ".git/rebase-apply/msg")
             (insert-file-contents ".git/rebase-apply/msg"))
            ((file-readable-p ".git/MERGE_MSG")
             (insert-file-contents ".git/MERGE_MSG")))
      ; delete empty lines at end
      (goto-char (point-min))
      (when (re-search-forward "\n+\\'" nil t)
        (replace-match "\n" t t))
      (when sign-off (git-append-sign-off committer-name committer-email)))
    buffer))

(define-derived-mode git-log-edit-mode log-edit-mode "Git-Log-Edit"
  "Major mode for editing git log messages.

Set up git-specific `font-lock-keywords' for `log-edit-mode'."
  (set (make-local-variable 'font-lock-defaults)
       '(git-log-edit-font-lock-keywords t t)))

(defun git-commit-file ()
  "Commit the marked file(s), asking for a commit message."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (when (git-run-pre-commit-hook)
    (let ((buffer (get-buffer-create "*git-commit*"))
          (coding-system (git-get-commits-coding-system))
          author-name author-email subject date)
      (when (eq 0 (buffer-size buffer))
        (when (file-readable-p ".git/rebase-apply/info")
          (with-temp-buffer
            (insert-file-contents ".git/rebase-apply/info")
            (goto-char (point-min))
            (when (re-search-forward "^Author: \\(.*\\)\nEmail: \\(.*\\)$" nil t)
              (setq author-name (match-string 1))
              (setq author-email (match-string 2)))
            (goto-char (point-min))
            (when (re-search-forward "^Subject: \\(.*\\)$" nil t)
              (setq subject (match-string 1)))
            (goto-char (point-min))
            (when (re-search-forward "^Date: \\(.*\\)$" nil t)
              (setq date (match-string 1)))))
        (git-setup-log-buffer buffer (git-get-merge-heads) author-name author-email subject date))
      (if (boundp 'log-edit-diff-function)
	  (log-edit 'git-do-commit nil '((log-edit-listfun . git-log-edit-files)
					 (log-edit-diff-function . git-log-edit-diff)) buffer 'git-log-edit-mode)
	(log-edit 'git-do-commit nil 'git-log-edit-files buffer
                  'git-log-edit-mode))
      (setq paragraph-separate (concat (regexp-quote git-log-msg-separator) "$\\|Author: \\|Date: \\|Merge: \\|Signed-off-by: \\|\f\\|[ 	]*$"))
      (setq buffer-file-coding-system coding-system)
      (re-search-forward (regexp-quote (concat git-log-msg-separator "\n")) nil t))))

(defun git-setup-commit-buffer (commit)
  "Setup the commit buffer with the contents of COMMIT."
  (let (parents author-name author-email subject date msg)
    (with-temp-buffer
      (let ((coding-system (git-get-logoutput-coding-system)))
        (git-call-process t "log" "-1" "--pretty=medium" "--abbrev=40" commit)
        (goto-char (point-min))
        (when (re-search-forward "^Merge: *\\(.*\\)$" nil t)
          (setq parents (cdr (split-string (match-string 1) " +"))))
        (when (re-search-forward "^Author: *\\(.*\\) <\\(.*\\)>$" nil t)
          (setq author-name (match-string 1))
          (setq author-email (match-string 2)))
        (when (re-search-forward "^Date: *\\(.*\\)$" nil t)
          (setq date (match-string 1)))
        (while (re-search-forward "^    \\(.*\\)$" nil t)
          (push (match-string 1) msg))
        (setq msg (nreverse msg))
        (setq subject (pop msg))
        (while (and msg (zerop (length (car msg))) (pop msg)))))
    (git-setup-log-buffer (get-buffer-create "*git-commit*")
                          parents author-name author-email subject date
                          (mapconcat #'identity msg "\n"))))

(defun git-get-commit-files (commit)
  "Retrieve a sorted list of files modified by COMMIT."
  (let (files)
    (with-temp-buffer
      (git-call-process t "diff-tree" "-m" "-r" "-z" "--name-only" "--no-commit-id" "--root" commit)
      (goto-char (point-min))
      (while (re-search-forward "\\([^\0]*\\)\0" nil t 1)
        (push (match-string 1) files)))
    (sort files #'string-lessp)))

(defun git-read-commit-name (prompt &optional default)
  "Ask for a commit name, with completion for local branch, remote branch and tag."
  (completing-read prompt
                   (list* "HEAD" "ORIG_HEAD" "FETCH_HEAD" (mapcar #'car (git-for-each-ref)))
		   nil nil nil nil default))

(defun git-checkout (branch &optional merge)
  "Checkout a branch, tag, or any commit.
Use a prefix arg if git should merge while checking out."
  (interactive
   (list (git-read-commit-name "Checkout: ")
         current-prefix-arg))
  (unless git-status (error "Not in git-status buffer."))
  (let ((args (list branch "--")))
    (when merge (push "-m" args))
    (when (apply #'git-call-process-display-error "checkout" args)
      (git-update-status-files))))

(defun git-branch (branch)
  "Create a branch from the current HEAD and switch to it."
  (interactive (list (git-read-commit-name "Branch: ")))
  (unless git-status (error "Not in git-status buffer."))
  (if (git-rev-parse (concat "refs/heads/" branch))
      (if (yes-or-no-p (format "Branch %s already exists, replace it? " branch))
          (and (git-call-process-display-error "branch" "-f" branch)
               (git-call-process-display-error "checkout" branch))
        (message "Canceled."))
    (git-call-process-display-error "checkout" "-b" branch))
    (git-refresh-ewoc-hf git-status))

(defun git-amend-commit ()
  "Undo the last commit on HEAD, and set things up to commit an
amended version of it."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (when (git-empty-db-p) (error "No commit to amend."))
  (let* ((commit (git-rev-parse "HEAD"))
         (files (git-get-commit-files commit)))
    (when (if (git-rev-parse "HEAD^")
              (git-call-process-display-error "reset" "--soft" "HEAD^")
            (and (git-update-ref "ORIG_HEAD" commit)
                 (git-update-ref "HEAD" nil commit)))
      (git-update-status-files files t)
      (git-setup-commit-buffer commit)
      (git-commit-file))))

(defun git-cherry-pick-commit (arg)
  "Cherry-pick a commit."
  (interactive (list (git-read-commit-name "Cherry-pick commit: ")))
  (unless git-status (error "Not in git-status buffer."))
  (let ((commit (git-rev-parse (concat arg "^0"))))
    (unless commit (error "Not a valid commit '%s'." arg))
    (when (git-rev-parse (concat commit "^2"))
      (error "Cannot cherry-pick a merge commit."))
    (let ((files (git-get-commit-files commit))
          (ok (git-call-process-display-error "cherry-pick" "-n" commit)))
      (git-update-status-files files ok)
      (with-current-buffer (git-setup-commit-buffer commit)
        (goto-char (point-min))
        (if (re-search-forward "^\n*Signed-off-by:" nil t 1)
            (goto-char (match-beginning 0))
          (goto-char (point-max)))
        (insert "(cherry picked from commit " commit ")\n"))
      (when ok (git-commit-file)))))

(defun git-revert-commit (arg)
  "Revert a commit."
  (interactive (list (git-read-commit-name "Revert commit: ")))
  (unless git-status (error "Not in git-status buffer."))
  (let ((commit (git-rev-parse (concat arg "^0"))))
    (unless commit (error "Not a valid commit '%s'." arg))
    (when (git-rev-parse (concat commit "^2"))
      (error "Cannot revert a merge commit."))
    (let ((files (git-get-commit-files commit))
          (subject (git-get-commit-description commit))
          (ok (git-call-process-display-error "revert" "-n" commit)))
      (git-update-status-files files ok)
      (when (string-match "^[0-9a-f]+ - \\(.*\\)$" subject)
        (setq subject (match-string 1 subject)))
      (git-setup-log-buffer (get-buffer-create "*git-commit*")
                            (git-get-merge-heads) nil nil (format "Revert \"%s\"" subject) nil
                            (format "This reverts commit %s.\n" commit))
      (when ok (git-commit-file)))))

(defun git-find-file ()
  "Visit the current file in its own buffer."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let ((info (ewoc-data (ewoc-locate git-status))))
    (unless (git-expand-directory info)
      (find-file (git-fileinfo->name info))
      (when (eq 'unmerged (git-fileinfo->state info))
        (smerge-mode 1)))))

(defun git-find-file-other-window ()
  "Visit the current file in its own buffer in another window."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let ((info (ewoc-data (ewoc-locate git-status))))
    (find-file-other-window (git-fileinfo->name info))
    (when (eq 'unmerged (git-fileinfo->state info))
      (smerge-mode))))

(defun git-find-file-imerge ()
  "Visit the current file in interactive merge mode."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let ((info (ewoc-data (ewoc-locate git-status))))
    (find-file (git-fileinfo->name info))
    (smerge-ediff)))

(defun git-view-file ()
  "View the current file in its own buffer."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (let ((info (ewoc-data (ewoc-locate git-status))))
    (view-file (git-fileinfo->name info))))

(defun git-refresh-status ()
  "Refresh the git status buffer."
  (interactive)
  (unless git-status (error "Not in git-status buffer."))
  (message "Refreshing git status...")
  (git-update-status-files)
  (message "Refreshing git status...done"))

(defun git-status-quit ()
  "Quit git-status mode."
  (interactive)
  (bury-buffer))

;;;; Major Mode
;;;; ------------------------------------------------------------

(defvar git-status-mode-hook nil
  "Run after `git-status-mode' is setup.")

(defvar git-status-mode-map nil
  "Keymap for git major mode.")

(defvar git-status nil
  "List of all files managed by the git-status mode.")

(unless git-status-mode-map
  (let ((map (make-keymap))
        (commit-map (make-sparse-keymap))
        (diff-map (make-sparse-keymap))
        (toggle-map (make-sparse-keymap)))
    (suppress-keymap map)
    (define-key map "?"   'git-help)
    (define-key map "h"   'git-help)
    (define-key map " "   'git-next-file)
    (define-key map "a"   'git-add-file)
    (define-key map "c"   'git-commit-file)
    (define-key map "\C-c" commit-map)
    (define-key map "d"    diff-map)
    (define-key map "="   'git-diff-file)
    (define-key map "f"   'git-find-file)
    (define-key map "\r"  'git-find-file)
    (define-key map "g"   'git-refresh-status)
    (define-key map "i"   'git-ignore-file)
    (define-key map "I"   'git-insert-file)
    (define-key map "l"   'git-log-file)
    (define-key map "m"   'git-mark-file)
    (define-key map "M"   'git-mark-all)
    (define-key map "n"   'git-next-file)
    (define-key map "N"   'git-next-unmerged-file)
    (define-key map "o"   'git-find-file-other-window)
    (define-key map "p"   'git-prev-file)
    (define-key map "P"   'git-prev-unmerged-file)
    (define-key map "q"   'git-status-quit)
    (define-key map "r"   'git-remove-file)
    (define-key map "t"    toggle-map)
    (define-key map "T"   'git-toggle-all-marks)
    (define-key map "u"   'git-unmark-file)
    (define-key map "U"   'git-revert-file)
    (define-key map "v"   'git-view-file)
    (define-key map "x"   'git-remove-handled)
    (define-key map "\C-?" 'git-unmark-file-up)
    (define-key map "\M-\C-?" 'git-unmark-all)
    ; the commit submap
    (define-key commit-map "\C-a" 'git-amend-commit)
    (define-key commit-map "\C-b" 'git-branch)
    (define-key commit-map "\C-o" 'git-checkout)
    (define-key commit-map "\C-p" 'git-cherry-pick-commit)
    (define-key commit-map "\C-v" 'git-revert-commit)
    ; the diff submap
    (define-key diff-map "b" 'git-diff-file-base)
    (define-key diff-map "c" 'git-diff-file-combined)
    (define-key diff-map "=" 'git-diff-file)
    (define-key diff-map "e" 'git-diff-file-idiff)
    (define-key diff-map "E" 'git-find-file-imerge)
    (define-key diff-map "h" 'git-diff-file-merge-head)
    (define-key diff-map "m" 'git-diff-file-mine)
    (define-key diff-map "o" 'git-diff-file-other)
    ; the toggle submap
    (define-key toggle-map "u" 'git-toggle-show-uptodate)
    (define-key toggle-map "i" 'git-toggle-show-ignored)
    (define-key toggle-map "k" 'git-toggle-show-unknown)
    (define-key toggle-map "m" 'git-toggle-all-marks)
    (setq git-status-mode-map map))
  (easy-menu-define git-menu git-status-mode-map
    "Git Menu"
    `("Git"
      ["Refresh" git-refresh-status t]
      ["Commit" git-commit-file t]
      ["Checkout..." git-checkout t]
      ["New Branch..." git-branch t]
      ["Cherry-pick Commit..." git-cherry-pick-commit t]
      ["Revert Commit..." git-revert-commit t]
      ("Merge"
	["Next Unmerged File" git-next-unmerged-file t]
	["Prev Unmerged File" git-prev-unmerged-file t]
	["Interactive Merge File" git-find-file-imerge t]
	["Diff Against Common Base File" git-diff-file-base t]
	["Diff Combined" git-diff-file-combined t]
	["Diff Against Merge Head" git-diff-file-merge-head t]
	["Diff Against Mine" git-diff-file-mine t]
	["Diff Against Other" git-diff-file-other t])
      "--------"
      ["Add File" git-add-file t]
      ["Revert File" git-revert-file t]
      ["Ignore File" git-ignore-file t]
      ["Remove File" git-remove-file t]
      ["Insert File" git-insert-file t]
      "--------"
      ["Find File" git-find-file t]
      ["View File" git-view-file t]
      ["Diff File" git-diff-file t]
      ["Interactive Diff File" git-diff-file-idiff t]
      ["Log" git-log-file t]
      "--------"
      ["Mark" git-mark-file t]
      ["Mark All" git-mark-all t]
      ["Unmark" git-unmark-file t]
      ["Unmark All" git-unmark-all t]
      ["Toggle All Marks" git-toggle-all-marks t]
      ["Hide Handled Files" git-remove-handled t]
      "--------"
      ["Show Uptodate Files" git-toggle-show-uptodate :style toggle :selected git-show-uptodate]
      ["Show Ignored Files" git-toggle-show-ignored :style toggle :selected git-show-ignored]
      ["Show Unknown Files" git-toggle-show-unknown :style toggle :selected git-show-unknown]
      "--------"
      ["Quit" git-status-quit t])))


;; git mode should only run in the *git status* buffer
(put 'git-status-mode 'mode-class 'special)

(defun git-status-mode ()
  "Major mode for interacting with Git.
Commands:
\\{git-status-mode-map}"
  (kill-all-local-variables)
  (buffer-disable-undo)
  (setq mode-name "git status"
        major-mode 'git-status-mode
        goal-column 17
        buffer-read-only t)
  (use-local-map git-status-mode-map)
  (let ((buffer-read-only nil))
    (erase-buffer)
  (let ((status (ewoc-create 'git-fileinfo-prettyprint "" "")))
    (set (make-local-variable 'git-status) status))
  (set (make-local-variable 'list-buffers-directory) default-directory)
  (make-local-variable 'git-show-uptodate)
  (make-local-variable 'git-show-ignored)
  (make-local-variable 'git-show-unknown)
  (run-hooks 'git-status-mode-hook)))

(defun git-find-status-buffer (dir)
  "Find the git status buffer handling a specified directory."
  (let ((list (buffer-list))
        (fulldir (expand-file-name dir))
        found)
    (while (and list (not found))
      (let ((buffer (car list)))
        (with-current-buffer buffer
          (when (and list-buffers-directory
                     (string-equal fulldir (expand-file-name list-buffers-directory))
		     (eq major-mode 'git-status-mode))
            (setq found buffer))))
      (setq list (cdr list)))
    found))

(defun git-status (dir)
  "Entry point into git-status mode."
  (interactive "DSelect directory: ")
  (setq dir (git-get-top-dir dir))
  (if (file-directory-p (concat (file-name-as-directory dir) ".git"))
      (let ((buffer (or (and git-reuse-status-buffer (git-find-status-buffer dir))
                        (create-file-buffer (expand-file-name "*git-status*" dir)))))
        (switch-to-buffer buffer)
        (cd dir)
        (git-status-mode)
        (git-refresh-status)
        (goto-char (point-min))
        (add-hook 'after-save-hook 'git-update-saved-file))
    (message "%s is not a git working tree." dir)))

(defun git-update-saved-file ()
  "Update the corresponding git-status buffer when a file is saved.
Meant to be used in `after-save-hook'."
  (let* ((file (expand-file-name buffer-file-name))
         (dir (condition-case nil (git-get-top-dir (file-name-directory file)) (error nil)))
         (buffer (and dir (git-find-status-buffer dir))))
    (when buffer
      (with-current-buffer buffer
        (let ((filename (file-relative-name file dir)))
          ; skip files located inside the .git directory
          (unless (string-match "^\\.git/" filename)
            (git-call-process nil "add" "--refresh" "--" filename)
            (git-update-status-files (list filename))))))))

(defun git-help ()
  "Display help for Git mode."
  (interactive)
  (describe-function 'git-status-mode))

(provide 'git)
;;; git.el ends here
