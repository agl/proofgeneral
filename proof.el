;; proof.el Major mode for proof assistants
;; Copyright (C) 1994 - 1997 LFCS Edinburgh. 
;; Authors: Yves Bertot, Healfdene Goguen, Thomas Kleymann and Dilip Sequeira

;; Maintainer: LEGO Team <lego@dcs.ed.ac.uk>
;; Thanks to David Aspinall, Robert Boyer, Rod Burstall,
;;           James McKinna, Mark Ruys, Martin Steffen, Perdita Stevens  


;; TO DO:

;; o Make lego code buffer local
;; o Need to think about fixing up errors caused by pbp-generated commands
;; o Comments should be replaced by single spaces unless at start of line
;; o Error is not signaled if an import fails
;; o Comments need to be treated as separate proof commands, for
;;   otherwise undoing a proof command may lead to a comment
;;   accidently being removed.
;; o Proof mode breaks if an error is encounterred during the import
;;   phase. We need better support for multiple modules
;; o proof-undo-last-successful-command needs to be extended so that
;;   it deletes regions of the script buffer when invoked outside a proof 
;; o undo support needs to consider Discharge; perhaps unrol to the
;;   beginning of the module? 

;; $Log$
;; Revision 1.10.2.14  1997/10/08 08:22:35  hhg
;; Updated undo, fixed bugs, more modularization
;;
;; Revision 1.10.2.13  1997/10/07 13:27:51  hhg
;; New structure sharing as much as possible between LEGO and Coq.
;;
;; Revision 1.10.2.12  1997/10/03 14:52:53  tms
;; o Replaced (string= "str" (substring cmd 0 n))
;;         by (string-match "^str" cmd)
;;   The latter doesn't raise an exception if cmd is too short
;;
;; o proof-segment-up-to: changed 5000 to 50000
;;   This should be more flexible!
;;
;; o updated lego-undoable-commands-regexp
;;
;; o lego-count-undos: now depends on lego-undoable-commands-regexp
;;                     with special treatment of Equiv
;;
;; Revision 1.10.2.11  1997/09/19 11:23:23  tms
;; o replaced ?\; by proof-terminal-char
;; o fixed a bug in proof-process-active-terminator
;;
;; Revision 1.10.2.10  1997/09/12 12:33:41  tms
;; improved lego-find-and-forget
;;
;; Revision 1.10.2.9  1997/09/11 15:39:19  tms
;; fixed a bug in proof-retract-until-point
;;

(require 'compile)
(require 'comint)
(require 'etags)
(require 'proof-fontlock)

(autoload 'w3-fetch "w3" nil t)

(defmacro deflocal (var value docstring)
 (list 'progn
   (list 'defvar var 'nil docstring)
   (list 'make-variable-buffer-local (list 'quote var))
   (list 'setq var value)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;               Configuration                                      ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Essentially everything is buffer local, so that we could run multiple
; shells, each with a goals buffer and multiple associated text buffers
; Variable naming convention is that everything which starts with 
; pbp is for the goals buffer, everything which starts proof-shell
; is in the shell buffer, and everything else is in script buffers

(deflocal proof-shell-echo-input t
  "If nil, input to the proof shell will not be echoed")

(deflocal proof-prog-name-ask-p nil
  "*If t, you will be asked which program to run when the inferior
 process starts up.")

(deflocal pbp-change-goal nil
  "*Command to change to the goal %s")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  Other buffer-local variables used by proof mode                 ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; These should be set before proof-config-done is called

(deflocal proof-terminal-char nil "terminator character")

(deflocal proof-comment-start nil "Comment start")
(deflocal proof-comment-end nil "Comment end")

(deflocal proof-save-command-regexp nil "")
(deflocal proof-save-with-hole-regexp nil "")
(deflocal proof-goal-command-regexp nil "")
(deflocal proof-goal-with-hole-regexp nil "")

(deflocal proof-undo-target-fn nil "")
(deflocal proof-forget-target-fn nil "")

(deflocal proof-forget-id-command nil "")
(deflocal proof-kill-goal-command nil "")

;; these should be set in proof-pre-shell-start-hook

(deflocal proof-prog-name nil "program name for proof shell")
(deflocal proof-mode-for-shell nil "mode for proof shell")
(deflocal proof-mode-for-pbp nil "The actual mode for Proof-by-Pointing.")
(deflocal proof-shell-config nil 
  "Function to config proof-system to interface")

(defvar proof-pre-shell-start-hook)
(defvar proof-post-shell-exit-hook)

(deflocal proof-shell-prompt-pattern nil 
   "comint-prompt-pattern for proof shell")

(deflocal proof-shell-init-cmd nil
   "The command for initially configuring the proof process")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  Generic config for script management                            ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deflocal proof-shell-wakeup-char ""
  "A character terminating the prompt in annotation mode")

(deflocal proof-shell-annotated-prompt-regexp ""
  "Annotated prompt pattern")

(deflocal proof-shell-abort-goal-regexp nil
  "*Regular expression indicating that the proof of the current goal
  has been abandoned.")

(deflocal proof-shell-error-regexp nil
  "A regular expression indicating that the PROOF process has
  identified an error.") 

(deflocal proof-shell-proof-completed-regexp nil
  "*Regular expression indicating that the proof has been completed.")

(deflocal proof-shell-result-start ""
  "String indicating the start of an output from the prover following
  a `pbp-goal-command' or a `pbp-hyp-command'.")

(deflocal proof-shell-result-end ""
  "String indicating the end of an output from the prover following a
  `pbp-goal-command' or a `pbp-hyp-command'.") 

(deflocal proof-shell-start-goals-regexp ""
  "String indicating the start of the proof state.")

(deflocal proof-shell-end-goals-regexp ""
  "String indicating the end of the proof state.")

(deflocal proof-shell-sanitise t "sanitise output?")

(deflocal pbp-error-regexp nil
  "A regular expression indicating that the PROOF process has
  identified an error.") 

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  Internal variables used by scripting and pbp                    ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deflocal proof-terminal-string nil 
  "You are not authorised for this information.")

(deflocal proof-re-end-of-cmd nil 
  "You are not authorised for this information.")

(deflocal proof-re-term-or-comment nil 
  "You are not authorised for this information.")

(deflocal proof-locked-ext nil
  "You are not authorised for this information.")

(deflocal proof-queue-ext nil
  "You are not authorised for this information.")

(deflocal proof-mark-ext nil 
  "You are not authorised for this information.")

(deflocal proof-buffer-for-shell nil
  "You are not authorised for this information.")

(deflocal proof-shell-script-buffer nil
  "You are not authorised for this information.")

(deflocal proof-shell-pbp-buffer nil
  "You are not authorised for this information.")

(deflocal pbp-shell-buffer nil
  "You are not authorised for this information.")

(deflocal pbp-script-buffer nil
  "You are not authorised for this information.")

(deflocal proof-shell-busy nil 
  "You are not authorised for this information.")

(deflocal proof-buffer-type nil 
  "You are not authorised for this information.")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;               Bridging the emacs19/xemacs gulf                   ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar running-xemacs  nil)
(defvar running-emacs19 nil)

(setq running-xemacs  (string-match "XEmacs\\|Lucid" emacs-version))
(or running-xemacs
    (setq running-emacs19 (string-match "^19\\." emacs-version)))

;; courtesy of Mark Ruys 
(defun emacs-version-at-least (major minor)
  "Test if emacs version is at least major.minor"
  (or (> emacs-major-version major)
      (and (= emacs-major-version major) (>= emacs-minor-version minor)))
)

(defvar extended-shell-command-on-region
  (emacs-version-at-least 19 29)
  "Does `shell-command-on-region' optionally offer to output in an other buffer?")

;; in case Emacs is not aware of read-shell-command-map
(defvar read-shell-command-map
  (let ((map (make-sparse-keymap)))
    (if (not (fboundp 'set-keymap-parents))
        (setq map (append minibuffer-local-map map))
      (set-keymap-parents map minibuffer-local-map)
      (set-keymap-name map 'read-shell-command-map))
    (define-key map "\t" 'comint-dynamic-complete)
    (define-key map "\M-\t" 'comint-dynamic-complete)
    (define-key map "\M-?" 'comint-dynamic-list-completions)
    map)
  "Minibuffer keymap used by shell-command and related commands.")


;; in case Emacs is not aware of the function read-shell-command
(or (fboundp 'read-shell-command)
    ;; from minibuf.el distributed with XEmacs 19.11
    (defun read-shell-command (prompt &optional initial-input history)
      "Just like read-string, but uses read-shell-command-map:
\\{read-shell-command-map}"
      (let ((minibuffer-completion-table nil))
        (read-from-minibuffer prompt initial-input read-shell-command-map
                              nil (or history
                              'shell-command-history)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;          A couple of small utilities                             ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun string-to-list (s separator) 
  "converts strings `s' separated by the character `separator' to a
  list of words" 
  (let ((end-of-word-occurence (string-match (concat separator "+") s)))
    (if (not end-of-word-occurence)
        (if (string= s "") 
            nil
          (list s))
      (cons (substring s 0 end-of-word-occurence) 
            (string-to-list 
             (substring s
                        (string-match (concat "[^" separator "]")
                                      s end-of-word-occurence)) separator)))))

(defun w3-remove-file-name (address)
  "remove the file name in a World Wide Web address"
  (string-match "://[^/]+/" address)
  (concat (substring address 0 (match-end 0))
          (file-name-directory (substring address (match-end 0)))))

(defun set-queue-prop (property value)
  (set-extent-property proof-queue-ext property value))

(defun get-queue-prop (property)
  (extent-property proof-queue-ext property))

(defun set-locked-prop (property value)
  (set-extent-property proof-locked-ext property value))

(defun get-locked-prop (property)
  (extent-property proof-locked-ext property))

(defun set-extent-start (extent value)
  (set-extent-endpoints extent value (extent-end-position extent)))

(defun set-extent-end (extent value)
  (set-extent-endpoints extent (extent-start-position extent) value))

(defmacro pbp-shell-val (var)
  (list 'save-excursion (list 'set-buffer 'pbp-shell-buffer)
	                var))

(defun proof-end-of-locked ()
  (or (extent-end-position proof-locked-ext) (point-min)))

(defun proof-goto-end-of-locked ()
  "Jump to the end of the locked region."
  (interactive)
  (goto-char (proof-end-of-locked)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  Starting and stopping the proof-system shell                    ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun proof-shell-live-buffer () 
  (if (and proof-buffer-for-shell
	   (comint-check-proc proof-buffer-for-shell))
       proof-buffer-for-shell))

(defun proof-start-shell ()
  (if (proof-shell-live-buffer)
      ()
    (run-hooks 'proof-pre-shell-start-hook)
    (if proof-prog-name-ask-p
	(save-excursion
	  (setq proof-prog-name (read-shell-command "Run process: "
						    proof-prog-name))))
    (let ((proc
	   (concat "Inferior "
		   (substring proof-prog-name
			      (string-match "[^/]*$" proof-prog-name)))))
      (while (get-buffer (concat "*" proc "*"))
	(if (string= (substring proc -1) ">")
	    (aset proc (- (length proc) 2) 
		  (+ 1 (aref proc (- (length proc) 2))))
	  (setq proc (concat proc "<2>"))))

      (message (format "Starting %s process..." proc))

      (let ((prog-name-list (string-to-list proof-prog-name " ")))
	(apply 'make-comint  (append (list proc (car prog-name-list) nil)
				     (cdr prog-name-list))))

      (setq proof-buffer-for-shell (get-buffer (concat "*" proc "*")))

      (let ((shell-mode proof-mode-for-shell) 
            (pbp-mode proof-mode-for-pbp)
	    (shellbuf proof-buffer-for-shell)
	    (scriptbuf (current-buffer)))
	(save-excursion
	  (set-buffer shellbuf)
	  (setq proof-shell-script-buffer scriptbuf)
	  (setq proof-shell-pbp-buffer 
		(get-buffer-create (concat "*" proc "-goals*")))
	  (put 'proof-shell-script-buffer 'permanent-local t) 
	  (put 'proof-shell-pbp-buffer 'permanent-local t)
	  (funcall shell-mode)
	  (set-buffer proof-shell-pbp-buffer)
	  (funcall pbp-mode)
	  (setq pbp-shell-buffer shellbuf)
	  (setq pbp-script-buffer scriptbuf)))

      (message 
       (format "Starting %s process... done." proc)))))
  

(defun proof-stop-shell ()
  "Exit the PROOF process

  Runs proof-shell-exit-hook if non nil"

  (interactive)
  (save-excursion
    (let ((buffer (proof-shell-live-buffer)) (proc))
      (if buffer
	  (progn
	    (save-excursion
	      (set-buffer buffer)
	      (setq proc (process-name (get-buffer-process)))
	      (comint-send-eof)
	      (save-excursion
		(set-buffer proof-shell-script-buffer)
		(detach-extent proof-queue-ext))
	      (kill-buffer))
	    (run-hooks 'proof-shell-exit-hook)

             ;;it is important that the hooks are
	     ;;run after the buffer has been killed. In the reverse
	     ;;order e.g., intall-shell-fonts causes problems and it
	     ;;is impossilbe to restart the PROOF shell

	    (message (format "%s process terminated." proc)))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;          Proof by pointing                                       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defconst pbp-goal-command "Pbp %s;"
  "Command informing the prover that `pbp-button-action' has been
  requested on a goal.")


(defconst pbp-hyp-command "PbpHyp %s;"
  "Command informing the prover that `pbp-button-action' has been
  requested on an assumption.")

(defvar pbp-keymap (make-keymap 'Pbp-keymap) 
  "Keymap for proof mode")

(defun pbp-button-action (event)
   (interactive "e")
   (mouse-set-point event)
   (pbp-construct-command))

(define-key pbp-keymap 'button2 'pbp-button-action)

; Using the extents in a mouse behavior is quite simple: from the
; mouse position, find the relevant extent, then get its annotation
; and produce a piece of text that will be inserted in the right
; buffer.  Attaching this behavior to the mouse is simply done by
; attaching a keymap to all the extents.

(defun proof-expand-path (string)
  (let ((a 0) (l (length string)) ls)
    (while (< a l) 
      (setq ls (cons (int-to-string (aref string a)) 
		     (cons " " ls)))
      (incf a))
    (apply 'concat (nreverse ls))))

(defun pbp-construct-command ()
  (let* ((ext (extent-at (point) () 'proof))
	 (top-ext (extent-at (point) () 'proof-top-element))
	 (top-info (extent-property top-ext 'proof-top-element)) 
	 path cmd)
    (if (extentp top-ext)
	(cond 
	 ((extentp ext)
	  (setq path (concat (cdr top-info)
			     (proof-expand-path (extent-property ext 'proof))))
	  (setq cmd
		(if (eq 'hyp (car top-info))
		    (format pbp-hyp-command path)
		  (format pbp-goal-command path)))
	  (pop-to-buffer pbp-script-buffer)
	  (proof-invisible-command cmd))
	 (t
	  (if (eq 'hyp (car top-info))
	      (progn
		(setq cmd (format pbp-hyp-command (cdr top-info)))
		(pop-to-buffer pbp-script-buffer)
		(proof-invisible-command cmd))
	      (setq cmd (format pbp-change-goal (cdr top-info)))
	      (pop-to-buffer pbp-script-buffer)
	      (proof-insert-pbp-command cmd)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;          Turning annotated output into pbp goal set              ;;
;;          All very lego-specific at present                       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deflocal proof-shell-first-special-char nil "where the specials start")
(deflocal proof-shell-goal-char nil "goal mark")
(deflocal proof-shell-start-char nil "annotation start")
(deflocal proof-shell-end-char nil "annotation end")
(deflocal proof-shell-field-char nil "annotated field end")
(deflocal proof-shell-eager-annotation-start nil "eager ann. field start")
(deflocal proof-shell-eager-annotation-end nil "eager ann. field end")

(defconst proof-shell-assumption-regexp nil
  "A regular expression matching the name of assumptions.")

(defconst proof-shell-goal-regexp nil
  "A regular expressin matching the identifier of a goal.")

(defconst proof-shell-noise-regexp nil
  "Unwanted information output from the proof process within
  `proof-start-goals-regexp' and `proof-end-goals-regexp'.")

(defun pbp-make-top-extent (start end)
  (let (extent name)
    (goto-char start)
    (setq name (cond 
		((looking-at proof-shell-goal-regexp)
		 (cons 'goal (match-string 1)))
		((looking-at proof-shell-assumption-regexp)
		 (cons 'hyp (match-string 1)))))
    (beginning-of-line)
    (setq start (point))
    (goto-char end)
    (beginning-of-line)
    (backward-char)
    (setq extent (make-extent start (point)))
    (set-extent-property extent 'mouse-face 'highlight)
    (set-extent-property extent 'keymap pbp-keymap)
    (set-extent-property extent 'proof-top-element name)))

(defun proof-shell-analyse-structure (string)
  (save-excursion
    (let* ((ip 0) (op 0) ap (l (length string)) 
	   (ann (make-string (length string) ?x))
           (stack ()) (topl ()) 
	   (out (make-string l ?x )) c ext)
      (while (< ip l)
	(setq c (aref string ip))
	(if (< c proof-shell-first-special-char)
	    (progn (aset out op c)
		   (incf op))
	  (cond 
	   ((= c proof-shell-goal-char)
	    (setq topl (append topl (list (+ 1 op)))))
	   ((= c proof-shell-start-char)	    
	    (setq ap (- (aref string (incf ip)) 32))
	    (incf ip)
	    (while (not (= (aref string ip) proof-shell-end-char))
	      (aset ann ap (- (aref string ip) 32))
	      (incf ap)
	      (incf ip))
	    (setq stack (cons op (cons (substring ann 0 ap) stack))))
	   ((= c proof-shell-field-char)
	    (setq ext (make-extent (car stack) op out))
	    (set-extent-property ext 'mouse-face 'highlight)
	    (set-extent-property ext 'keymap pbp-keymap)
	    (set-extent-property ext 'proof (cadr stack))
	    (set-extent-property ext 'duplicable t)
	    (setq stack (cddr stack)))))
	(incf ip))
      (display-buffer (set-buffer proof-shell-pbp-buffer))
      (erase-buffer)
      (insert (substring out 0 op)))))
;      (while (setq ip (car topl) 
;		   topl (cdr topl))
;	(pbp-make-top-extent ip (car topl)))
;      (pbp-make-top-extent ip (point-max)))))

(defun proof-shell-strip-annotations (string)
  (let* ((ip 0) (op 0) (l (length string)) (out (make-string l ?x )))
    (while (< ip l)
      (if (>= (aref string ip) proof-shell-first-special-char)
	  (if (char-equal (aref string ip) proof-shell-start-char)
	      (progn (incf ip)
		     (while (< (aref string ip) proof-shell-first-special-char)
		       (incf ip))))
	(aset out op (aref string ip))
	(incf op))
      (incf ip))
    (substring out 0 op)))

(defun proof-shell-handle-error (cmd string)
  (save-excursion 
    (display-buffer (set-buffer proof-shell-pbp-buffer))
    (goto-char (point-max))
    (if (re-search-backward pbp-error-regexp nil t) 
	(delete-region (- (point) 2) (point-max)))
    (newline 2)
    (insert-string string)
    (beep))
  (set-buffer proof-shell-script-buffer)
  (detach-extent proof-queue-ext)
  (mapcar-extents 'delete-extent nil (current-buffer) 
		  (proof-end-of-locked) (point-max) nil 'type)
  (proof-release-process))

(deflocal proof-shell-delayed-output nil
  "The last interesting output the proof process output, and what to do
   with it.")

(defun proof-shell-handle-delayed-output ()
  (let ((ins (car proof-shell-delayed-output))
	(str (cdr proof-shell-delayed-output)))
    (display-buffer proof-shell-pbp-buffer)
    (save-excursion
      (cond 
       ((eq ins 'insert)
	(setq str (proof-shell-strip-annotations str))
	(set-buffer proof-shell-pbp-buffer)
	(insert str))
       ((eq ins 'analyse)
	(proof-shell-analyse-structure str))
       (t (set-buffer proof-shell-pbp-buffer)
	  (insert "\n\nbug???")))))
  (setq proof-shell-delayed-output (cons 'insert "done")))


(defun proof-shell-process-output (cmd string)
  (cond 
   ((string-match proof-shell-error-regexp string)
    (cons 'error (proof-shell-strip-annotations string)))

   ((string-match proof-shell-abort-goal-regexp string)
    (setq proof-shell-delayed-output (cons 'insert "\n\nAborted"))
    ())
	 
   ((string-match proof-shell-proof-completed-regexp string)
    (setq proof-shell-delayed-output
	  (cons 'insert (concat "\n" (match-string 0 string)))))

   ((string-match proof-shell-start-goals-regexp string)
    (let (start end)
      (while (progn (setq start (match-end 0))
		    (string-match proof-shell-start-goals-regexp 
				  string start)))
      (string-match proof-shell-end-goals-regexp string start)
      (setq proof-shell-delayed-output 
	    (cons 'analyse (substring string start end)))))
       
   ((string-match proof-shell-result-start string)
    (let (start end)
      (setq start (+ 1 (match-end 0)))
      (string-match proof-shell-result-end string)
      (setq end (- (match-beginning 0) 1))
      (cons 'loopback (substring string start end))))
   
   ((string-match "^Module" cmd)
    (setq proof-shell-delayed-output (cons 'insert "Imports done!")))

   (t (setq proof-shell-delayed-output (cons 'insert string)))))
         
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;   Low-level commands for shell communication                     ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun proof-shell-insert (string)
  (goto-char (point-max))
  (insert (funcall proof-shell-config) string)
  (if (not (extent-property proof-mark-ext 'detached))
      (set-extent-endpoints proof-mark-ext (point) (point)))
  (comint-send-input))

(defun proof-send (string)
  (let ((l (length string)) (i 0))
    (while (< i l)
      (if (= (aref string i) ?\n) (aset string i ?\ ))
      (incf i)))
  (save-excursion
    (set-buffer proof-buffer-for-shell)
    (proof-shell-insert string)))

;; grab the process and return t, otherwise return nil. Note that this
;; is not really intended for anything complicated - just to stop the
;; user accidentally sending a command while the queue is running.

(defun proof-check-process-available ()
  (save-excursion
    (if (proof-shell-live-buffer)
	(progn (set-buffer proof-buffer-for-shell)
	       (if proof-shell-busy (error "Proof Process Busy!"))))))

(defun proof-grab-process ()
  (save-excursion
    (proof-start-shell)
    (let ((buf (current-buffer)))
      (set-buffer proof-buffer-for-shell)
      (if proof-shell-busy	       
	  (error "proof process busy")
	(if (not (eq proof-shell-script-buffer buf))
	    (error "Bug: Don't own process") 
	  (setq proof-shell-busy t)
	  t)))))

(defun proof-release-process ()
  (if (proof-shell-live-buffer)
      (save-excursion
	(let ((buf (current-buffer)))
	  (set-buffer proof-buffer-for-shell)
	  (if (not proof-shell-busy)
	      (error "Bug: Proof process not busy")
	    (if (not (eq proof-shell-script-buffer buf)) 
		(error "Bug: Don't own process")
	      (setq proof-shell-busy nil)))))))

(defun proof-start-queue (start end alist &optional obj)
  (proof-grab-process) ; TODO: catch error and delete extents in queue
  (save-excursion
    (set-buffer proof-buffer-for-shell)
    (erase-buffer proof-shell-pbp-buffer))
  (setq proof-shell-delayed-output (cons 'insert "Done."))
  (if (null obj) (setq obj (current-buffer)))
  (set-extent-endpoints proof-queue-ext start end obj)
  (set-queue-prop 'action-list alist)
  (proof-send (cadar alist)))

; returns t if it's run out of input

(defun proof-shell-exec-loop ()
  (save-excursion
    (set-buffer proof-shell-script-buffer)
    (let* ((a (get-queue-prop 'action-list))
	   (ext (caar a))
	   (act (caddar a)))
      (if (null act) (error "BUG2"))
      (funcall act ext)
      (setq a (cdr a))
      (set-queue-prop 'action-list a)
      (if (null a)
	  (progn (proof-release-process)
		 (detach-extent proof-queue-ext)
		 t)
	(proof-send (cadar a))
	()))))

(defun proof-shell-insert-loopback-cmd  (cmd)
  "Insert command sequence triggered by the proof process
at the end of locked region (after inserting a newline)."
  (save-excursion
    (set-buffer proof-shell-script-buffer)
    (let (start ext ls)
      (goto-char (setq start (proof-end-of-locked)))
      (newline)
      (insert cmd)
      (setq ext (make-extent start (point)))
      (set-extent-property ext 'type 'pbp)
      (set-extent-property ext 'cmd cmd)
      (setq ls (get-queue-prop 'action-list))
      (set-extent-endpoints proof-queue-ext start (point) (current-buffer))
      (set-queue-prop 'action-list 
		      (cons (car ls) 
			    (cons (list ext cmd 'proof-done-advancing)
				  (cdr ls)))))))

(defun proof-shell-popup-eager-annotation ()
  (let (mrk str)
    (save-excursion 
      (goto-char (point-max))
      (search-backward proof-shell-eager-annotation-start)
      (setq mrk (+ 1 (point)))
      (search-forward proof-shell-eager-annotation-end)
      (setq str (buffer-substring mrk (- (point) 1)))
      (display-buffer (set-buffer proof-shell-pbp-buffer))
      (insert str "\n"))))
      
(defun proof-shell-filter (str) 
  (if (string-match proof-shell-eager-annotation-end str)
      (proof-shell-popup-eager-annotation))
  (if (string-match (char-to-string proof-shell-wakeup-char) str)
      (if (extent-property proof-mark-ext 'detached)
	  (progn
	    (goto-char (point-min))
	    (re-search-forward proof-shell-annotated-prompt-regexp)
	    (set-extent-endpoints proof-mark-ext (point) (point))
	    (backward-delete-char 1))
	(let (string mrk res cmd)	
	    (goto-char (setq mrk (extent-start-position proof-mark-ext)))
	    (re-search-forward proof-shell-annotated-prompt-regexp nil t)
	    (set-extent-endpoints proof-mark-ext (point) (point))
	    (backward-char (- (match-end 0) (match-beginning 0)))
	    (setq string (buffer-substring mrk (point)))
	    (if proof-shell-sanitise 
		(progn
		  (delete-region mrk (point))
		  (insert (proof-shell-strip-annotations string))))
	    (goto-char (extent-start-position proof-mark-ext))
	    (backward-delete-char 1)
	    (save-excursion
	      (set-buffer proof-shell-script-buffer)
	      (setq cmd (cadar (get-queue-prop 'action-list))))
	    (save-excursion
	      (setq res (proof-shell-process-output cmd string))
	      (cond
	       ((and (consp res) (eq (car res) 'error))
		(proof-shell-handle-error cmd (cdr res)))
	       ((and (consp res) (eq (car res) 'loopback))
		(proof-shell-insert-loopback-cmd (cdr res))
		(proof-shell-exec-loop))
	       (t (if (proof-shell-exec-loop)
		      (proof-shell-handle-delayed-output)))))))))
	    
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;          Script management                                     ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	
; Script management uses two major extents: Locked, which marks text
; which has been sent to the proof assistant and cannot be altered
; without being retracted, and Queue, which contains stuff being
; queued for processing.  Queue has a property 'action-list' which
; contains a list of (extent,command,action) triples. The loop looks
; like: Execute the command, and if it's successful, do action on
; extent.  If the command's not successful, we bounce the rest of the
; queue and do some error processing.
;
; 'goalsave - denoting a 'goalsave pair in the locked region
;    a 'goalsave region has a 'name property which is the name of the goal
; 'pbp - denoting an extent created by pbp
; 'vanilla - denoting any other extent.
;   'pbp & 'vanilla extents have a property 'cmd, which says what
;   command they contain. 

; We don't allow commands while the queue has anything in it.  So we
; do configuration by concatenating the config command on the front in
; proof-send

(defun proof-done-invisible (ext) ())

(defun proof-invisible-command (cmd)
  (proof-check-process-available)
  (if (not (string-match proof-re-end-of-cmd cmd))
      (setq cmd (concat cmd proof-terminal-string)))
  (proof-start-queue 0 (length cmd) 
		     (list (list (make-extent 0 (length cmd) cmd) cmd
				 'proof-done-invisible))
		     cmd))

(defun proof-insert-pbp-command (cmd)
  (proof-check-process-available)
  (let (start ext)
    (goto-char (setq start (proof-end-of-locked)))
    (insert cmd)
    (setq ext (make-extent start (point)))
    (set-extent-property ext 'type 'pbp)
    (set-extent-property ext 'cmd cmd)
    (proof-start-queue start (point) (list (list ext cmd 
						 'proof-done-advancing)))))

(defun proof-done-advancing (ext)
  (let ((end (extent-end-position ext)) cmd nam gext next)
    (set-extent-endpoints proof-locked-ext 1 end)
    (set-extent-start proof-queue-ext end)
    (setq cmd (extent-property ext 'cmd))
    (if (not (string-match proof-save-command-regexp cmd))
	(set-extent-property ext 'highlight 'mouse-face)
      (if (string-match proof-save-with-hole-regexp cmd)
	  (setq nam (match-string 2 cmd)))
      (setq gext ext)
      (while (progn (setq cmd (extent-property gext 'cmd))
		    (not (string-match proof-goal-command-regexp cmd)))
	(setq next (extent-at (extent-start-position gext) nil 
			      'type nil 'before))
	(delete-extent gext)
	(setq gext next))
      (if (null nam)
	  (if (string-match proof-goal-with-hole-regexp cmd)
	      (setq nam (match-string 2 cmd))
 	    (error "Oops... can't find Goal name!!!")))
      (set-extent-end gext end)
      (set-extent-property gext 'highlight 'mouse-face)
      (set-extent-property gext 'type 'goalsave)
      (set-extent-property gext 'name nam))))

; Create a list of (int,string) pairs from the end of the locked
; region to pos, denoting the command and the position of its
; terminator. Return 'comment consed on the front if we're inside a
; comment

; Remark tms: It would be better to have comments as separate 

(defun proof-segment-up-to (pos)
  (save-excursion
    (let ((str (make-string 50000 ?x)) 
	  (i 0) (depth 0) done alist c)
     (proof-goto-end-of-locked)
      (while (not done)
	(cond 
	 ((and (= (point) pos) (> depth 0))
	  (setq done t alist (append alist (list 'comment))))
	 ((= (point) (point-max))
	  (setq done t))
	 ((looking-at "\\*)")
	  (if (= depth 0) 
	      (progn (message "Warning: extraneous comment end") (setq done t))
	    (setq depth (- depth 1)) (forward-char 2)))
	 ((looking-at "(\\*")
	  (setq depth (+ depth 1)) (forward-char 2))
	 ((> depth 0) (forward-char))
	 (t
	  (setq c (char-after (point)))
	  (if (or (> i 0) (not (= (char-syntax c) ?\ )))
	      (progn (aset str i c) (setq i (+ 1 i))))	  
	  (forward-char)
	  (if (= c proof-terminal-char)
	      (progn 
		(setq alist (cons (list (substring str 0 i) (point)) alist))
		(if (>= (point) pos) (setq done t) (setq i 0)))))))
      (nreverse alist))))

(defun proof-semis-to-vanillas (semis)
  (let ((ct (proof-end-of-locked)) ext alist cmd)
    (while (not (null semis))
      (setq ext (make-extent ct (cadar semis))
            cmd (caar semis)
	    ct (cadar semis))
      (set-extent-property ext 'type 'vanilla)
      (set-extent-property ext 'cmd cmd)
      (setq alist (cons (list ext cmd 'proof-done-advancing) alist))
      (setq semis (cdr semis)))
    (nreverse alist)))

(defun proof-assert-until-point ()
  (interactive)
  (proof-check-process-available)
  (if (not (eq proof-buffer-type 'script))
      (error "Must be running in a script buffer"))
  (if (not (re-search-backward "\\S-" (proof-end-of-locked) t))
      (error "Nothing to do!"))
  (let (semis)			 
    (setq semis (proof-segment-up-to (point)))
    (if (or (null semis) (eq semis (list 'comment))) (error "Nothing to do!"))
    (if (eq 'comment (car semis)) (setq semis (cdr semis)))
    (goto-char (cadar (last semis)))
    (proof-start-queue (proof-end-of-locked) (point)
		       (proof-semis-to-vanillas semis))))
    
(defun proof-done-retracting (ext &optional delete-region)
  "Updates display after proof process has reset its state. See also
the documentation for `proof-retract-until-point'. It optionally
deletes the region corresponding to the proof sequence."
  (let ((start (extent-start-position ext))
        (end (extent-end-position ext)))
    (set-extent-end proof-locked-ext start)
    (set-extent-end proof-queue-ext start)
    (mapcar-extents 'delete-extent nil (current-buffer) start end  nil 'type)
    (delete-extent ext)
    (and delete-region (delete-region start end))))

(deflocal proof-undoable-commands-regexp nil "commands that can be undone")

(defun coq-count-undos (sext)
  (let ((ct 0) str)
    (while sext
      (setq str (extent-property sext 'cmd))
      (if (string-match proof-undoable-commands-regexp str)
	  (setq ct (+ 1 ct)))
      (setq sext (extent-at (extent-end-position sext) nil 'type nil 'after)))
  (concat "Undo " (int-to-string ct) proof-terminal-string)))

(defun coq-find-and-forget (sext)
  (let (str ans)
    (while sext
      (if (eq (extent-property sext 'type) 'goalsave)
	  (setq ans (concat proof-forget-id-command
			    (extent-property sext 'name) proof-terminal-string)
		sext nil)
	(setq str (extent-property sext 'cmd))
	(cond

	 ((string-match (concat "\\`\\("
				(ids-to-regexp (append coq-keywords-decl
						       coq-keywords-defn))
				"\\)\\s-*\\(\\w+\\)\\s-*:") str)
	  (setq ans (concat proof-forget-id-command
			    (match-string 2 str) proof-terminal-string)
		sext nil))

	 (t 
	  (setq sext 
		(extent-at (extent-end-position sext) nil 'type nil 
			   'after))))))
    (or ans
	(concat "echo \"Nothing more to Forget.\"" proof-terminal-string))))

(defun lego-count-undos (sext)
  (let ((ct 0) str i)
    (while sext
      (setq str (extent-property sext 'cmd))
      (if (eq (extent-property sext 'type) 'vanilla)
	(if (or (string-match proof-undoable-commands-regexp str)
		(and (string-match "Equiv" str)
		     (not (string-match "Equiv\\s +[TV]Reg" str))))
	    (setq ct (+ 1 ct)))
	(setq i 0)
	(while (< i (length str)) 
	  (if (= (aref str i) proof-terminal-char) (setq ct (+ 1 ct)))
	  (setq i (+ 1 i))))
      (setq sext (extent-at (extent-end-position sext) nil 'type nil 'after)))
  (concat "Undo " (int-to-string ct) proof-terminal-string)))

(defun lego-find-and-forget (sext) 
  (let (str ans)
    (while sext
      (if (eq (extent-property sext 'type) 'goalsave)
	  (setq ans (concat proof-forget-id-command
			    (extent-property sext 'name) proof-terminal-string)
		sext nil)
	(setq str (extent-property sext 'cmd))
	(cond

	 ;; matches e.g., "[a,b:T]"
	 ((string-match (concat "\\`" (lego-decl-defn-regexp "[:|=]")) str)
	  (let ((ids (match-string 1 str))) ; returns "a,b"
	    (string-match proof-id ids)	; matches "a"
	    (setq ans (concat proof-forget-id-command (match-string 1 ids)
			      proof-terminal-string)
		  sext nil)))

	 ((string-match "\\`\\(Inductive\\|\\Record\\)\\s-*\\[\\s-*\\w+\\s-*:[^;]+\\`Parameters\\\s-*\\[\\s-*\\(\\w+\\)\\s-*:" str)
	  (setq ans (concat proof-forget-id-command (match-string 2 str)
			    proof-terminal-string)
		sext nil))

	 ((string-match "\\`\\(Inductive\\|Record\\)\\s-*\\[\\s-*\\(\\w+\\)\\s-*:" str)
	  (setq ans (concat proof-forget-id-command
			    (match-string 2 str) proof-terminal-string)
		sext nil))

	 ((string-match "\\`\\s-*Module\\s-+\\(\\S-+\\)\\W" str)
	  (setq ans (concat "ForgetMark " (match-string 1 str) proof-terminal-string)
		sext nil))
	 (t 
	  (setq sext 
		(extent-at (extent-end-position sext) nil 'type nil 
			   'after))))))
    (or ans
	(concat "echo \"Nothing more to Forget.\"" proof-terminal-string))))

(defun proof-retract-setup-actions (start end proof-command delete-region)
  (list (list (make-extent start end)
	      proof-command
	      `(lambda (ext) (proof-done-retracting ext ,delete-region)))))

(defun proof-retract-until-point (&optional delete-region)
  "Sets up the proof process for retracting until point. In
   particular, it sets a flag for the filter process to call
   `proof-done-retracting' after the proof process has actually
   successfully reset its state. It optionally deletes the region in
   the proof script corresponding to the proof command sequence."
  (interactive)
  (proof-check-process-available)
  (if (not (eq proof-buffer-type 'script))
      (error "Must be running in a script buffer"))
  (let ((sext (extent-at (point) nil 'type))
	(end (extent-end-position proof-locked-ext))
	ext start actions done)
    (if (null end) (error "No locked region"))
    (if (or (null sext) (< end (point))) (error "Outside locked region"))
    (setq start (extent-start-position sext))
    
    (setq ext (extent-at end nil 'type nil 'before))

    (while (and ext (not done))		  
      (cond 
       ((eq (extent-property ext 'type) 'goalsave)
	(setq done t))
       ((string-match proof-goal-command-regexp (extent-property ext 'cmd))
	(setq done 'goal))
       (t
	(setq ext (extent-at (extent-start-position ext) nil
			     'type nil 'before)))))

    (if (eq done 'goal) 
	(if (<= (extent-end-position ext) (point))
	    (setq actions
		  (proof-retract-setup-actions
		   start end (funcall proof-undo-target-fn sext) delete-region)
		  end start)
	  (setq actions
		(proof-retract-setup-actions (extent-start-position ext) end
					     proof-kill-goal-command
					     delete-region)
		end (extent-start-position ext))))

    (if (> end start) 
	(setq actions 
	      (proof-retract-setup-actions start end
					   (funcall
					    proof-forget-target-fn sext)
					   delete-region)))
    (proof-start-queue (min start end)
		       (extent-end-position proof-locked-ext)
		       actions)))

(defun proof-undo-last-successful-command ()
  "Undo last successful command, both in the buffer recording the
   proof script and in the proof process. In particular, it deletes
   the corresponding part of the proof script."
  (interactive)
  (let* ((eol (proof-end-of-locked))
    ; this is inefficient because it searches for the last extent by
    ; beginning at the start of the buffer. Is there a better way?
	(start-of-prev-cmd
	 (extent-start-position 
	  (last-element (mapcar-extents (lambda (e) e) nil nil
					(point-min) eol nil 'cmd)))))

   
    (goto-char start-of-prev-cmd) 
    (proof-retract-until-point t)))

(defun proof-restart-script ()
  (interactive)
  (if (not (eq proof-buffer-type 'script))
      (error "Restart in script buffer"))
  (mapcar-extents 'delete-extent nil 
		  (current-buffer) (point-min)  (point-max) nil 'type)
  (detach-extent proof-locked-ext)
  (detach-extent proof-queue-ext)
  (if (get-buffer proof-buffer-for-shell) 
      (progn
	(save-excursion 
	  (set-buffer proof-buffer-for-shell)
	  (setq proof-shell-busy nil)
	  (if (get-buffer proof-shell-pbp-buffer)
	      (kill-buffer proof-shell-pbp-buffer)))
	(kill-buffer proof-buffer-for-shell))))
	  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;          Active terminator minor mode                            ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(deflocal proof-active-terminator-minor-mode nil 
"active terminator minor mode flag")

(make-variable-buffer-local 'proof-active-terminator-minor-mode)
(put 'proof-active-terminator-minor-mode 'permanent-local t)

(defun proof-active-terminator-minor-mode (&optional arg)
  "Toggle PROOF's Active Terminator minor mode.
With arg, turn on the Active Terminator minor mode if and only if arg
is positive.

If Active terminator mode is enabled, a terminator will process the
current command."

 (interactive "P")
 
;; has this minor mode been registered as such?
  (or (assq 'proof-active-terminator-minor-mode minor-mode-alist)
      (setq minor-mode-alist
            (append minor-mode-alist
                    (list '(proof-active-terminator-minor-mode
			    (concat " " proof-terminal-string))))))

 (setq proof-active-terminator-minor-mode
        (if (null arg) (not proof-active-terminator-minor-mode)
          (> (prefix-numeric-value arg) 0)))
   (if (fboundp 'redraw-modeline) (redraw-modeline) (redraw-modeline)))

(defun proof-active-terminator ()
  (interactive)
  (if proof-active-terminator-minor-mode 
      (proof-process-active-terminator)
    (self-insert-command 1)))

(defun proof-process-active-terminator ()
  "Insert the terminator in an intelligent way and send the commands
  between the previous and the new terminator to the proof process."
  (proof-check-process-available)
  (let ((mrk (point)) ins semis)
    (if (looking-at "\\s-\\|\\'\\|\\w") 
	(if (not (re-search-backward "\\S-" (proof-end-of-locked) t))
	    (error "Nothing to do!")))
    (if (not (= (char-after (point)) proof-terminal-char))
	(progn (forward-char) (insert proof-terminal-string) (setq ins t)))
    (setq semis (proof-segment-up-to (point)))    
    (if (null semis) (error "Nothing to do!"))
    (if (eq 'comment (car semis)) 
	(progn (if ins (backward-delete-char 1))
	       (goto-char mrk) (insert proof-terminal-string))
      (goto-char (cadar (last semis)))
      (proof-start-queue (proof-end-of-locked) (point)
			 (proof-semis-to-vanillas semis)))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Proof mode configuration                                         ;;
;; Eventually there will be some more                               ;;
;; functionality here common to both coq and lego.                  ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(define-derived-mode proof-mode fundamental-mode 
  "Proof" "Proof mode - not standalone"
  (setq proof-buffer-type 'script)
  (setq proof-queue-ext (make-extent nil nil (current-buffer)))
  (setq proof-locked-ext (make-extent nil nil (current-buffer)))
  (set-queue-prop 'start-closed t)
  (set-queue-prop 'end-open t)
  (set-queue-prop 'read-only t)
  (make-face 'proof-queue-face)
  (set-face-background 'proof-queue-face "mistyrose")
  (set-queue-prop 'face 'proof-queue-face)
  
  (set-locked-prop 'start-closed t)
  (set-locked-prop 'end-open t)
  (set-locked-prop 'read-only t)
  (make-face 'proof-locked-face)
  (set-face-background 'proof-locked-face "lavender")
  (set-locked-prop 'face 'proof-locked-face)
  (make-local-hook 'proof-pre-shell-start-hook)
  (make-local-hook 'proof-shell-exit-hook)

)

;; the following callback is an irritating hack - there should be some
;; elegant mechanism for computing constants after the child has
;; configured.

(defun proof-config-done () 

;; calculate some strings and regexps for searching

  (setq proof-terminal-string (char-to-string proof-terminal-char))

  (make-local-variable 'comment-start)
  (setq comment-start (concat proof-comment-start " "))
  (make-local-variable 'comment-end)
  (setq comment-end (concat " " proof-comment-end))
  (make-local-variable 'comment-start-skip)
  (setq comment-start-skip 
    (concat (regexp-quote proof-comment-start) "+\\s_?"))

  (setq proof-re-end-of-cmd (concat "\\s_*" proof-terminal-string "\\s_*\\\'"))
  (setq proof-re-term-or-comment 
	(concat proof-terminal-string "\\|" (regexp-quote proof-comment-start)
		"\\|" (regexp-quote proof-comment-end)))


;; keymap

  (define-key proof-mode-map
    (vconcat [(control c)] (vector proof-terminal-char))
    'proof-active-terminator-minor-mode)

  (define-key proof-mode-map proof-terminal-char 'proof-active-terminator)
  (define-key proof-mode-map [(control c) (control a)]    'proof-assert-until-point)
  (define-key proof-mode-map [(control c) u]    'proof-retract-until-point)
  (define-key proof-mode-map [(control c) (control u)] 'proof-undo-last-successful-command)
  (define-key proof-mode-map [(control c) ?']
  'proof-goto-end-of-locked)

  ;; For fontlock
  (remove-hook 'font-lock-after-fontify-buffer-hook 'proof-zap-commas-buffer t)
  (add-hook 'font-lock-after-fontify-buffer-hook 'proof-zap-commas-buffer nil t)
  (remove-hook 'font-lock-mode-hook 'proof-unfontify-separator t)
  (add-hook 'font-lock-mode-hook 'proof-unfontify-separator nil t)

;; if we don't have the following, zap-commas fails to work.

  (setq font-lock-always-fontify-immediately t))

(define-derived-mode proof-shell-mode comint-mode 
  "proof-shell" "Proof shell mode - not standalone"
  (setq proof-buffer-type 'shell)
  (setq proof-shell-busy nil)
  (setq proof-shell-sanitise t)
  (setq proof-shell-delayed-output (cons 'insert "done"))
  (setq comint-prompt-regexp proof-shell-prompt-pattern)
  (add-hook 'comint-output-filter-functions 'proof-shell-filter nil t)
;  (add-hook 'comint-output-filter-functions 'comint-truncate-buffer nil t)
;  (setq comint-buffer-maximum-size 10000)
  (setq comint-append-old-input nil)
  (setq proof-mark-ext (make-extent nil nil (current-buffer)))
  (set-extent-property proof-mark-ext 'detachable nil)
  (set-extent-property proof-mark-ext 'start-closed t)
  (set-extent-property proof-mark-ext 'end-open t))

(defun proof-shell-config-done ()
  (accept-process-output (get-buffer-process (current-buffer)))
;  (proof-shell-insert proof-shell-init-cmd)
  (while (extent-property proof-mark-ext 'detached)
    (if (accept-process-output (get-buffer-process (current-buffer)) 5)
	()
      (error "Failed to initialise proof process"))))

(define-derived-mode pbp-mode fundamental-mode 
  (setq proof-buffer-type 'pbp)
  "Proof" "Proof by Pointing"
  ;; defined-derived-mode pbp-mode initialises pbp-mode-map
  (suppress-keymap pbp-mode-map)
  (erase-buffer))

(provide 'proof)
