;; proof-script.el  Major mode for proof assistant script files.
;;
;; Copyright (C) 1994 - 1999 LFCS Edinburgh. 
;; Authors: David Aspinall, Yves Bertot, Healfdene Goguen,
;;          Thomas Kleymann and Dilip Sequeira
;;
;; Maintainer:  Proof General maintainer <proofgen@dcs.ed.ac.uk>
;;
;; $Id$
;;
;; FIXME da: use of point-min and point-max everywhere is wrong
;; if narrowing is in force.

(require 'proof)

(require 'proof-syntax)

;; If it's disabled by proof-script-indent, it won't need to be
;; loaded.
(autoload 'proof-indent-line "proof-indent" 
	   "Indent current line of proof script")


;; Spans are our abstraction of extents/overlays.
(eval-and-compile
  (cond ((fboundp 'make-extent) (require 'span-extent))
	((fboundp 'make-overlay) (require 'span-overlay))))

;; Nuke some byte-compiler warnings
(eval-when-compile
  (if (locate-library "func-menu") (require 'func-menu))
  (require 'comint))

;; FIXME:
;; More autoloads for proof-shell (added to nuke warnings,
;; maybe some should be 'official' exported functions in proof.el)
;; This helps see interface between proof-script / proof-shell.
(eval-when-compile
  (mapcar (lambda (f) 
	    (autoload f "proof-shell"))
	  '(proof-shell-ready-prover
	    proof-start-queue
	    proof-shell-live-buffer
	    proof-shell-invisible-command)))
;; proof-response-buffer-display now in proof.el, removed from above.

;; FIXME: *variable* proof-shell-proof-completed is declared in proof-shell
;; and used here.  Should be moved to proof.el or removed from here.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Internal variables used by script mode
;;

(deflocal proof-active-buffer-fake-minor-mode nil
  "An indication in the modeline that this is the *active* script buffer")



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Configuration of function-menu (aka "fume")	
;;
;; This code is only enabled if the user loads func-menu into Emacs.
;;
;; da:cleaned

(eval-after-load "func-menu"	'(progn	; BEGIN if func-menu

(deflocal proof-script-last-entity nil
  "Record of last entity found.   A hack for entities that are named
in two places, so that find-next-entity doesn't return the same values
twice.")

(defun proof-script-find-next-entity (buffer)
  "Find the next entity for function menu in a proof script.
A value for fume-find-function-name-method-alist for proof scripts.
Uses fume-function-name-regexp, which is intialised from 
proof-script-next-entity-regexps, which see."
  ;; Hopefully this function is fast enough.
  (set-buffer buffer)
  ;;  could as well use next-entity-regexps directly since this is
  ;;  not really meant to be used as a general function. 
  (let ((anyentity	(car fume-function-name-regexp)))
    (if (re-search-forward anyentity nil t)
	;; We've found some interesting entity, but have to find out
	;; which one, and where it begins.  
	(let ((entity (buffer-substring (match-beginning 0) (match-end 0)))
	      (start (match-beginning 0))
	      (discriminators (cdr fume-function-name-regexp))
	      (p (point))
	      disc res)
	  (while (and (not res) (setq disc (car-safe discriminators)))
	    (if (proof-string-match (car disc) entity)
		(let ((name (substring
			     entity
			     (match-beginning (nth 1 disc))
			     (match-end (nth 1 disc)))))
		  (cond
		   ((eq (nth 2 disc) 'backward)
		    (setq start
			  (or (re-search-backward (nth 3 disc) nil t)
			      start))
		    (goto-char p))
		   ((eq (nth 2 disc) 'forward)
		    (re-search-forward (nth 3 disc))))
		  (setq res (cons name start)))
	      (setq discriminators (cdr discriminators))))
	  res))))

))					; END if func-menu




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Basic code for the locked region and the queue region            ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; da FIXME: clean this section

(deflocal proof-locked-span nil
  "The locked span of the buffer.
Each script buffer has its own locked span, which may be detached
from the buffer.
Proof General allows buffers in other modes also to be locked;
these also have a non-nil value for this variable.")

;; da: really we only need one queue span rather than one per buffer,
;; but I've made it local because the initialisation occurs in
;; proof-init-segmentation, which can happen when a file is visited.
;; So nasty things might happen if a locked file is visited whilst
;; another buffer has a non-empty queue region being processed.

(deflocal proof-queue-span nil
  "The queue span of the buffer.  May be detached if inactive or empty.")

;; FIXME da: really the queue region should always be locked strictly.

(defun proof-span-read-only (span)
  "Make span be read-only, if proof-strict-read-only is non-nil.
Otherwise make span give a warning message on edits."
  (if proof-strict-read-only
      (span-read-only span)
    (span-write-warning span)))

;; not implemented yet; toggle via restarting scripting
;; (defun proof-toggle-strict-read-only ()
;;  "Toggle proof-strict-read-only, changing current spans."
;;  (interactive)
;;   map-spans blah
;;  )

(defun proof-init-segmentation ()
  "Initialise the queue and locked spans in a proof script buffer.
Allocate spans if need be.  The spans are detached from the
buffer, so the regions are made empty by this function."
  ;; Initialise queue span, remove it from buffer.
  (unless proof-queue-span
      (setq proof-queue-span (make-span 1 1)))
  (set-span-property proof-queue-span 'start-closed t)
  (set-span-property proof-queue-span 'end-open t)
  (proof-span-read-only proof-queue-span)
  (set-span-property proof-queue-span 'face 'proof-queue-face)
  (detach-span proof-queue-span)
  ;; Initialise locked span, remove it from buffer
  (unless proof-locked-span
      (setq proof-locked-span (make-span 1 1)))
  (set-span-property proof-locked-span 'start-closed t)
  (set-span-property proof-locked-span 'end-open t)
  (proof-span-read-only proof-locked-span)
  (set-span-property proof-locked-span 'face 'proof-locked-face)
  (detach-span proof-locked-span))

;; These two functions are used in coq.el to edit the locked region
;; (by lifting local (nested) lemmas out of a proof, to make them global).   
(defsubst proof-unlock-locked ()
  "Make the locked region writable.  
Used in lisp programs for temporary editing of the locked region.
See proof-lock-unlocked for the reverse operation."
  (span-read-write proof-locked-span))

(defsubst proof-lock-unlocked ()
  "Make the locked region read only (according to proof-strict-read-only).
Used in lisp programs for temporary editing of the locked region.
See proof-unlock-locked for the reverse operation."
  (proof-span-read-only proof-locked-span))

(defsubst proof-set-queue-endpoints (start end)
  "Set the queue span to be START, END."
  (set-span-endpoints proof-queue-span start end))

(defsubst proof-set-locked-endpoints (start end)
  "Set the locked span to be START, END."
  (set-span-endpoints proof-locked-span start end))

(defsubst proof-detach-queue ()
  "Remove the span for the queue region."
  (and proof-queue-span (detach-span proof-queue-span)))

(defsubst proof-detach-locked ()
  "Remove the span for the locked region."
  (and proof-locked-span (detach-span proof-locked-span)))

(defsubst proof-set-queue-start (start)
  "Set the queue span to begin at START."
  (set-span-start proof-queue-span start))

;; FIXME da: optional arg here was ignored, have fixed.
;; Do we really need it though?
(defun proof-detach-segments (&optional buffer)
  "Remove locked and queue region from BUFFER.
Defaults to current buffer when BUFFER is nil."
  (let ((buffer (or buffer (current-buffer))))
    (with-current-buffer buffer
      (proof-detach-queue)
      (proof-detach-locked))))

(defsubst proof-set-locked-end (end)
  "Set the end of the locked region to be END.
If END is at or before (point-min), remove the locked region.
Otherwise set the locked region to be from (point-min) to END."
  (if (>= (point-min) end)
      (proof-detach-locked)
    (set-span-endpoints proof-locked-span (point-min) end)
    ;; FIXME: the next line doesn't fix the disappearing regions
    ;; (was span property is lost in latest FSF Emacs, maybe?)
    ;; (set-span-property proof-locked-span 'face 'proof-locked-face)
    ))

;; Reimplemented this to mirror above because of remaining
;; span problen
(defsubst proof-set-queue-end (end)
  "Set the queue span to end at END."
  (if (or (>= (point-min) end)
	  (<= end (span-start proof-queue-span)))
      (proof-detach-queue)
    (set-span-end proof-queue-span end)))


;; FIXME: get rid of this function.  Some places expect this
;; to return nil if locked region is empty.	Moreover,
;; it confusingly returns the point past the end of the 
;; locked region.
(defun proof-locked-end ()
  "Return end of the locked region of the current buffer.
Only call this from a scripting buffer."
  (proof-unprocessed-begin))
  

(defsubst proof-end-of-queue ()
  "Return the end of the queue region, or nil if none."
  (and proof-queue-span (span-end proof-queue-span)))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Buffer position functions
;;
;; da:cleaned

(defun proof-unprocessed-begin ()
  "Return end of locked region in current buffer or (point-min) otherwise.
The position is actually one beyond the last locked character."
  (or 
   (and proof-locked-span 
	(span-end proof-locked-span))
   (point-min)))

(defun proof-script-end ()
  "Return the character beyond the last non-whitespace character.
This is the same position proof-locked-end ends up at when asserting
the script.  Works for any kind of buffer."
  (save-excursion
    (goto-char (point-max))
    (skip-chars-backward " \t\n")
    (point)))

(defun proof-queue-or-locked-end ()
  "Return the end of the queue region, or locked region, or (point-min).
This position should be the first writable position in the buffer.
An appropriate point to move point to (or make sure is displayed)
when a queue of commands is being processed."
  (or	
   ;; span-end returns nil if span is detatched
   (and proof-queue-span (span-end proof-queue-span))
   (and proof-locked-span (span-end proof-locked-span))
   (point-min)))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Predicates for locked region.  
;;
;; These work on any buffer, so that non-script buffers can be locked
;; (as processed files) too.
;;
;; da:cleaned

(defun proof-locked-region-full-p ()
  "Non-nil if the locked region covers all the buffer's non-whitespace.
Works on any buffer."
  (save-excursion
    (goto-char (point-max))
    (skip-chars-backward " \t\n")
    (>= (proof-unprocessed-begin) (point))))

(defun proof-locked-region-empty-p ()
  "Non-nil if the locked region is empty.  Works on any buffer."
  (eq (proof-unprocessed-begin) (point-min)))

(defun proof-only-whitespace-to-locked-region-p ()
  "Non-nil if only whitespace separates point from end of locked region.
Point should be after the locked region.
NB: If nil, point is left at first non-whitespace character found.
If non-nil, point is left where it was."
  (not (re-search-backward "\\S-" (proof-unprocessed-begin) t)))

(defun proof-in-locked-region-p ()
  "Non-nil if point is in locked region.  Assumes proof script buffer current."
  (< (point) (proof-unprocessed-begin)))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Misc movement functions
;;
;; da: cleaned

(defun proof-goto-end-of-locked ()
  "Jump to the end of the locked region."
  (goto-char (proof-unprocessed-begin)))

(defun proof-goto-end-of-locked-interactive ()
  "Switch to proof-script-buffer and jump to the end of the locked region.
Must be an active scripting buffer."
  (interactive)
  (switch-to-buffer proof-script-buffer)
  (goto-char (proof-unprocessed-begin)))

(defun proof-goto-end-of-locked-if-pos-not-visible-in-window ()
  "If the end of the locked region is not visible, jump to the end of it.
A possible hook function for proof-shell-handle-error-hook.
Does nothing if there is no active scripting buffer."
  (interactive)
  (if proof-script-buffer
      (let ((pos (with-current-buffer proof-script-buffer
		   (proof-locked-end)))
	    (win (get-buffer-window proof-script-buffer t)))
	(unless (and win (pos-visible-in-window-p pos))
	  (proof-goto-end-of-locked-interactive)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Multiple file handling
;;
;;
;; da:cleaned

(defun proof-complete-buffer-atomic (buffer)
  "Make sure BUFFER is marked as completely processed, completing with a single step.

If buffer already contains a locked region, only the remainder of the
buffer is closed off atomically.

This works for buffers which are not in proof scripting mode too,
to allow other files loaded by proof assistants to be marked read-only." 
;; FIXME: this isn't quite right, because not all of the structure 
;; in the locked region will be preserved when processing across several 
;; files.
;; In particular, the span for a currently open goal should be removed.
;; Keeping the structure is an approximation to make up for the fact
;; that that no structure is created by loading files via the 
;; proof assistant.
;; Future idea: proof assistant could ask Proof General to do the
;; loading, to alleviate file handling there?!
  (save-excursion
    (set-buffer buffer)
    (if (< (proof-unprocessed-begin) (proof-script-end))
	(let ((span (make-span (proof-unprocessed-begin) 
			       (proof-script-end)))
	      cmd)
	  (if (eq proof-buffer-type 'script) 
	      ;; For a script buffer
	      (progn
		(goto-char (point-min))
		(proof-find-next-terminator)
		(let ((cmd-list (member-if
				 (lambda (entry) (equal (car entry) 'cmd))
				 (proof-segment-up-to (point)))))
		  ;; Reset queue and locked regions.
		  (proof-init-segmentation)
		  (if cmd-list 
		      (progn
			(setq cmd (second (car cmd-list)))
			(set-span-property span 'type 'vanilla)
			(set-span-property span 'cmd cmd))
		    ;; If there was no command in the buffer, atomic span
		    ;; becomes a comment. This isn't quite right because
		    ;; the first ACS in a buffer could also be a goal-save
		    ;; span. We don't worry about this in the current
		    ;; implementation. This case should not happen in a
		    ;; LEGO module (because we assume that the first
		    ;; command is a module declaration). It should have no
		    ;; impact in Isabelle either (because there is no real
		    ;; retraction).
		    (set-span-property span 'type 'comment))))
	    ;; For a non-script buffer
	    (proof-init-segmentation)
	    (set-span-property span 'type 'comment))
	  ;; End of locked region is always end of buffer
	  (proof-set-locked-end (proof-script-end))))))

(defun proof-file-truename (filename)
  "Returns the true name of the file FILENAME or nil if file non-existent."
  (and filename (file-exists-p filename) (file-truename filename)))

(defun proof-file-to-buffer (filename)
  "Find a buffer visiting file FILENAME, or nil if there isn't one."
  (let* ((buffers (buffer-list))
	 (pos
	  (position (file-truename filename)
		    (mapcar 'proof-file-truename
			    (mapcar 'buffer-file-name
				    buffers))
		    :test 'equal)))
    (and pos (nth pos buffers))))

;; FIXME da: cleanup of odd asymmetry here: we have a nice setting for
;; proof-register-possibly-new-processed-file but something much more
;; complicated for retracting, because we allow a hook function
;; to calculate the new included files list.

(defun proof-register-possibly-new-processed-file (file &optional informprover)
  "Register a possibly new FILE as having been processed by the prover.
If INFORMPROVER is non-nil, the proof assistant will be told about this,
to co-ordinate with its internal file-management.  (Otherwise we assume
that it is a message from the proof assistant which triggers this call).

No action is taken if the file is already registered.

A warning message is issued if the register request came from the
proof assistant and Emacs is has a modified buffer visiting the file."
  (let* ((cfile (file-truename file))
	 (buffer (proof-file-to-buffer cfile)))
    (proof-debug (concat "Registering file " cfile 
			 (if (member cfile proof-included-files-list)
			     " (already registered, no action)." ".")))
    (unless (member cfile proof-included-files-list)
      (and buffer
	   (not informprover)
	   (buffer-modified-p buffer)
	   (proof-warning (concat "Changes to "
				  (buffer-name buffer)
				  " have not been saved!")))
      ;; Add the new file onto the front of the list
      (setq proof-included-files-list
	    (cons cfile proof-included-files-list))
      ;; If the file is loaded into a buffer, make sure it is completely locked
      (if buffer
	  (proof-complete-buffer-atomic buffer))
      ;; Tell the proof assistant, if we should and if we can
      (if (and informprover proof-shell-inform-file-processed-cmd)
	  (proof-shell-invisible-command 
	   (format proof-shell-inform-file-processed-cmd cfile) 
	   'wait)))))

(defun proof-inform-prover-file-retracted (rfile)
  (if (and informprover proof-shell-inform-file-retracted-cmd)
      (proof-shell-invisible-command
       (format proof-shell-inform-file-retracted-cmd rfile)
       'wait)))

(defun proof-auto-retract-dependencies (cfile &optional informprover)
  "Perhaps automatically retract the (linear) dependencies of CFILE.
If proof-auto-multiple-files is nil, no action is taken.
If CFILE does not appear on proof-included-files-list, no action taken.

Any buffers which are visiting files in proof-included-files-list
before CFILE are retracted using proof-protected-process-or-retract.
They are retracted in reverse order.

Since the proof-included-files-list is examined, we expect scripting
to be turned off before calling here (because turning it off could
otherwise change proof-included-files-list).

If INFORMPROVER is non-nil,  the proof assistant will be told about this,
using proof-shell-inform-file-retracted-cmd, to co-ordinate with its 
internal file-management.

Files which are not visited by any buffer are not retracted, on the
basis that we may not have the information necessary to retract them
-- spans that cover the buffer with definition/declaration
information.  A warning message is given for these cases, since it
could cause inconsistency problems.

NB!  Retraction can cause recursive calls of this function.
This is a subroutine for proof-unregister-buffer-file-name."
  (if proof-auto-multiple-files
      (let ((depfiles (cdr-safe
		       (member cfile (reverse proof-included-files-list))))
	    rfile rbuf)
	(while (setq rfile (car-safe depfiles))
	  ;; If there's a buffer visiting a dependent file, retract it.
	  ;; We test that the file to retract hasn't been retracted
	  ;; already by a recursive call here.  (But since we do retraction
	  ;; in reverse order, this shouldn't happen...)
	  (if (and (member rfile proof-included-files-list) 
		   (setq rbuf (proof-file-to-buffer rfile)))
	      (progn
		(proof-debug "Automatically retracting " rfile)
		(proof-protected-process-or-retract 'retract rbuf)
		(setq proof-included-files-list 
		      (delete rfile proof-included-files-list))
		;; Tell the proof assistant, if we should and we can.
		;; This may be useful if we synchronise the *prover* with
		;; PG's management of multiple files.  If the *prover*
		;; informs PG (better case), then we hope the prover will
		;; retract dependent files and we shouldn't use this
		;; degenerate (linear dependency) code.
		(if informprover
		    (proof-inform-prover-file-retracted rfile)))
	    ;; If no buffer available, issue a warning that nothing was done
	    (proof-warning "Not retracting unvisited file " rfile))
	  (setq depfiles (cdr depfiles))))))

(defun proof-unregister-buffer-file-name (&optional informprover)
  "Remove current buffer's filename from the list of included files.
No effect if the current buffer has no file name.
If INFORMPROVER is non-nil,  the proof assistant will be told about this,
using proof-shell-inform-file-retracted-cmd, to co-ordinate with its 
internal file-management.

If proof-auto-multiple-files is non-nil, any buffers on 
proof-included-files-list before this one will be automatically
retracted using proof-auto-retract-dependencies."
  (if buffer-file-name
      (let ((cfile (file-truename buffer-file-name)))
	(proof-debug (concat "Unregistering file " cfile 
			       (if (not (member cfile 
						proof-included-files-list))
				   " (not registered, no action)." ".")))
	(if (member cfile proof-included-files-list)
	    (progn
	      (proof-auto-retract-dependencies cfile informprover)
	      (setq proof-included-files-list
		    (delete cfile proof-included-files-list))
	      ;; Tell the proof assistant, if we should and we can.
	      ;; This case may be useful if there is a combined 
	      ;; management of multiple files between PG and prover.
	      (if informprover
		  (proof-inform-prover-file-retracted cfile)))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Activating and Deactivating Scripting
;;
;; 
;; da: cleaned

(defun proof-protected-process-or-retract (action &optional buffer)
  "If ACTION='process, process, If ACTION='retract, retract.
Process or retract the current buffer, which should be the active
scripting buffer, according to ACTION.
Retract buffer BUFFER if set, otherwise use the current buffer.
Gives a message in the minibuffer and busy-waits for the retraction
or processing to complete.  If it fails for some reason, 
an error is signalled here."
  (let ((fn   (cond ((eq action 'process) 'proof-process-buffer)
		    ((eq action 'retract) 'proof-retract-buffer)))
	(name (cond ((eq action 'process) "Processing")
		    ((eq action 'retract) "Retracting")))
	(buf  (or buffer (current-buffer))))
    (if fn
	(unwind-protect
	    (with-current-buffer buf
	      (message "%s buffer %s..." name buf)
	      (funcall fn)
	      (while proof-shell-busy ; busy wait
		(sit-for 1))
	      (message "%s buffer %s...done." name buf)
	      (sit-for 0))
	  ;; Test to see if action was successful
	  (with-current-buffer buf
	    (or (and (eq action 'retract) (proof-locked-region-empty-p))
		(and (eq action 'process) (proof-locked-region-full-p))
		(error "%s of %s failed!" name buf)))))))


(defun proof-deactivate-scripting (&optional forcedaction)
  "Deactivate scripting for the active scripting buffer.

Set proof-script-buffer to nil and turn off the modeline indicator.
No action if there is no active scripting buffer.  

We make sure that the active scripting buffer either has no locked
region or everything in it has been processed. This is done by
prompting the user or by automatically taking the action indicated in
the user option `proof-auto-action-when-deactivating-scripting.'

If the scripting buffer is (or has become) fully processed, and
it is associated with a file, it is registered on 
`proof-included-files-list'.  Conversely, if it is (or has become)
empty, make sure that it is *not* registered.  This is to
make sure that the included files list behaves as we might expect
with respect to the active scripting buffer, in an attempt to 
harmonize mixed scripting and file reading in the prover.

This function either succeeds, fails because the user 
refused to process or retract a partly finished buffer,
or gives an error message because retraction or processing failed.
If this function succeeds, then proof-script-buffer=nil afterwards.

The optional argument FORCEDACTION overrides the user option
`proof-auto-action-when-deactivating-scripting' and prevents
questioning the user.  It is used to make a value for
the kill-buffer-hook for scripting buffers, so that when
a scripting buffer is killed it is always retracted."
  (interactive)
  (if proof-script-buffer
      (with-current-buffer proof-script-buffer
	;; Examine buffer.

	;; We must ensure that the locked region is either 
	;; empty or full, to make sense for multiple-file
	;; scripting.  (A proof assistant won't be able to
	;; process just part of a file typically; moreover
	;; switching between buffers during a proof makes
	;; no sense.)
	(if (or (proof-locked-region-empty-p) 
		(proof-locked-region-full-p)
		;; Buffer is partly-processed
		(let*
		    ((action 
		      (or
		       forcedaction
		       proof-auto-action-when-deactivating-scripting
		       (progn
			 (save-window-excursion
			   (unless
			       ;; Test to see whether to display the 
			       ;; buffer or not.
			       ;; Could have user option here to avoid switching
			       ;; or maybe borrow similar standard setting
			       ;; save-some-buffers-query-display-buffer
			       (or
				(eq (current-buffer)
				    (window-buffer (selected-window)))
				(eq (selected-window) (minibuffer-window)))
			     (progn
			       (unless (one-window-p)
				 (delete-other-windows))
			       (switch-to-buffer proof-script-buffer t)))
			   ;; Would be nicer to ask a single question, but
			   ;; a nuisance to define our own dialogue since it
			   ;; doesn't really fit with one of the standard ones.
			   (cond
			    ((y-or-n-p
			      (format
			       "Scripting incomplete in buffer %s, retract? "
			       proof-script-buffer))
			     'retract)
			    ((y-or-n-p
			      (format
			       "Completely process buffer %s instead? "
			       proof-script-buffer))
			     'process)))))))
		  ;; Take the required action
		  (if action
		      (proof-protected-process-or-retract action)
		    ;; Give an acknowledgement to user's choice
		    ;; neither to assert or retract.  
		    (message "Scripting still active in %s" 
			     proof-script-buffer)
		    ;; Delay because this can be followed by an error
		    ;; message in proof-activate-scripting when trying
		    ;; to switch to another scripting buffer.
		    (sit-for 1)
		    nil)))

	    ;; If we get here, then the locked region is (now) either 
	    ;; completely empty or completely full.  
	    (progn
	      ;; We can immediately indicate that there is no active
	      ;; scripting buffer
	      (setq proof-script-buffer nil)

	      (if (proof-locked-region-full-p)
		  ;; If locked region is full, make sure that this buffer
		  ;; is registered on the included files list, and
		  ;; let the prover know it can consider it processed.
		  (if buffer-file-name
		      (proof-register-possibly-new-processed-file 
		       buffer-file-name
		       'tell-the-prover)))
	      
	      (if (proof-locked-region-empty-p)
		  ;; If locked region is empty, make sure this buffer is
		  ;; *off* the included files list. 
		  ;; FIXME: probably this isn't necessary: the
		  ;; file should be unregistered by the retract
		  ;; action, or in any case since it was only
		  ;; partly processed.
		  ;; FIXME 2: be careful about automatic
		  ;; multiple file handling here, since it calls
		  ;; for activating scripting elsewhere.
		  ;; We move the onus on unregistering now to
		  ;; the activate-scripting action.
		  (proof-unregister-buffer-file-name))

	      ;; Turn off Scripting indicator here.
	      (setq proof-active-buffer-fake-minor-mode nil)

	      ;; Make status of inactive scripting buffer show up
	      ;; FIXME da:
	      ;; not really necessary when called by kill buffer, at least.
	      (if (fboundp 'redraw-modeline)
		  (redraw-modeline)
		(force-mode-line-update)))))))
  
(defun proof-activate-scripting (&optional nosaves queuemode)
  "Ready prover and activate scripting for the current script buffer.

The current buffer is prepared for scripting. No changes are
necessary if it is already in Scripting minor mode. Otherwise, it
will become the new active scripting buffer, provided scripting
can be switched off in the previous active scripting buffer
with `proof-deactivate-scripting'.

Activating a new script buffer may be a good time to ask if the 
user wants to save some buffers; this is done if the user
option `proof-query-file-save-when-activating-scripting' is set
and provided the optional argument NOSAVES is non-nil.

The optional argument QUEUEMODE relaxes the test for a
busy proof shell to allow one which has mode QUEUEMODE.
In all other cases, a proof shell busy error is given.

Finally, the hooks `proof-activate-scripting-hook' are run.  
This can be a useful place to configure the proof assistant for
scripting in a particular file, for example, loading the
correct theory, or whatever."
  (interactive)
  ;; FIXME: the scope of this save-excursion is rather wide.
  ;; Problems without it however: Use button behaves oddly
  ;; when process is started already.
  ;; Where is save-excursion needed?
  ;; First experiment shows that it's the hooks that cause
  ;; problem, maybe even the use of proof-cd-sync (can't see why).
  (save-excursion
    (proof-shell-ready-prover queuemode)
    (cond 
     ((not (eq proof-buffer-type 'script)) 
      (error "Must be running in a script buffer!"))
     
     ;; If the current buffer is the active one there's nothing to do.
   ((equal (current-buffer) proof-script-buffer))
     
     ;; Otherwise we need to activate a new Scripting buffer.
   (t
      ;; If there's another buffer currently active, we need to 
      ;; deactivate it (also fixing up the included files list).
      (if proof-script-buffer
	  (progn
	    (proof-deactivate-scripting)
	    ;; Test whether deactivation worked
	    (if proof-script-buffer
		(error 
		 "You cannot have more than one active scripting buffer!"))))
	    
      ;; Now make sure that this buffer is off the included files
      ;; list.  In case we re-activate scripting in an already
      ;; completed buffer, it may be that the proof assistant
      ;; needs to retract some of this buffer's dependencies.
      (proof-unregister-buffer-file-name 'tell-the-prover)

      ;; If automatic retraction happened in the above step, we may
      ;; have inadvertently activated scripting somewhere else.
      ;; Better turn it off again.   This should succeed trivially.
      ;; NB: it seems that we could move the first test for an already
      ;; active buffer here, but it is more subtle: the first
      ;; deactivation can extend the proof-included-files list, which
      ;; would affect what retraction was done in
      ;; proof-unregister-buffer-file-name.
      (if proof-script-buffer
	  (proof-deactivate-scripting))
      (assert (null proof-script-buffer) 
	      "Bug in proof-activate-scripting: deactivate failed.")

      ;; Set the active scripting buffer, and initialise the 
      ;; queue and locked regions if necessary.
      (setq proof-script-buffer (current-buffer))
      (if (proof-locked-region-empty-p)
	  ;; This removes any locked region that was there, but
	  ;; sometimes we switch on scripting in "full" buffers,
	  ;; so mustn't do this.
	  (proof-init-segmentation))

      ;; Turn on the minor mode, make it show up.
      (setq proof-active-buffer-fake-minor-mode t)
      (if (fboundp 'redraw-modeline)
	  (redraw-modeline)
	(force-mode-line-update))
      
      ;; This may be a good time to ask if the user wants to save some
      ;; buffers.  On the other hand, it's jolly annoying to be
      ;; queried on the active scripting buffer if we've started
      ;; writing in it.  So pretend that one is unmodified, at least
      ;; (we certainly don't expect the proof assitant to load it)
      (if (and
	   proof-query-file-save-when-activating-scripting
	   (not nosaves))
	  (let ((modified (buffer-modified-p)))
	    (set-buffer-modified-p nil)
	    (unwind-protect
		(save-some-buffers)
 	      (set-buffer-modified-p modified))))

      ;; Run hooks with a variable which suggests whether or not 
      ;; to block.   NB: The hook function may send commands to the
      ;; process which will re-enter this function, but should exit 
      ;; immediately because scripting has been turned on now.
      (let
	  ((activated-interactively	(interactive-p)))
	(run-hooks 'proof-activate-scripting-hook))))))

(defun proof-toggle-active-scripting (&optional arg)
  "Toggle active scripting mode in the current buffer.
With ARG, turn on scripting iff ARG is positive."
  (interactive "P")
  ;; A little less obvious than it may seem: toggling scripting in the
  ;; current buffer may involve turning it off in some other buffer
  ;; first!
  (if (if (null arg)
	  (not (eq proof-script-buffer (current-buffer)))
	(> (prefix-numeric-value arg) 0))
      (progn
	(if proof-script-buffer 
	    (call-interactively (proof-deactivate-scripting)))
	(call-interactively (proof-activate-scripting)))
    (call-interactively (proof-deactivate-scripting))))

;; This function isn't such a wise idea: the buffer will often be fully
;; locked when writing a script, but we don't want to keep toggling
;; switching mode!
;;(defun proof-auto-deactivate-scripting ()
;;  "Turn off scripting if the current scripting buffer is empty or full.
;;This is a possible value for proof-state-change-hook.
;;FIXME: this currently doesn't quite work properly as a value for 
;;proof-state-change-hook, in fact: maybe because the
;;hook is called somewhere where proof-script-buffer
;;should not be nullified!"
;;  (if proof-script-buffer
;;      (with-current-buffer proof-script-buffer
;;	(if (or (proof-locked-region-empty-p)
;;		(proof-locked-region-full-p))
;;	    (proof-deactivate-scripting)))))

;;
;;  End of activating and deactivating scripting section
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; messy COMPATIBILITY HACKING for FSFmacs.
;; 
;; In case Emacs is not aware of the function read-shell-command,
;; and read-shell-command-map, we duplicate some code adjusted from
;; minibuf.el distributed with XEmacs 20.4.
;;
;; This code is still required as of FSF Emacs 20.2.
;;
;; I think bothering with this just to give completion for
;; when proof-prog-name-ask=t is a big overkill!   - da.
;;	
;; FIXME da: check code current in XEmacs 21.1

(defvar read-shell-command-map
  (let ((map (make-sparse-keymap 'read-shell-command-map)))
    (if (not (fboundp 'set-keymap-parents))
        (if (fboundp 'set-keymap-parent)
	    ;; FSF Emacs 20.2
	    (set-keymap-parent map minibuffer-local-map)
	  ;; Earlier FSF Emacs
	  (setq map (append minibuffer-local-map map))
	  ;; XEmacs versions?
	  (set-keymap-parents map minibuffer-local-map)))
    (define-key map "\t" 'comint-dynamic-complete)
    (define-key map "\M-\t" 'comint-dynamic-complete)
    (define-key map "\M-?" 'comint-dynamic-list-completions)
    map)
  "Minibuffer keymap used by shell-command and related commands.")

(or (fboundp 'read-shell-command)
    (defun read-shell-command (prompt &optional initial-input history)
      "Just like read-string, but uses read-shell-command-map:
\\{read-shell-command-map}"
      (let ((minibuffer-completion-table nil))
        (read-from-minibuffer prompt initial-input read-shell-command-map
                              nil (or history
                              'shell-command-history)))))


;;; end messy COMPATIBILITY HACKING
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;; da: NEW function added 28.10.98.
;; This is used by toolbar follow mode (which used to use the function
;; above).  [But wouldn't work for proof-shell-handle-error-hook?].

(defun proof-goto-end-of-queue-or-locked-if-not-visible ()
  "Jump to the end of the queue region or locked region if it isn't visible.
Assumes script buffer is current"
  (unless (pos-visible-in-window-p
	   (proof-queue-or-locked-end)
	   (get-buffer-window (current-buffer) t))
    (goto-char (proof-queue-or-locked-end))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;          User Commands                                           ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	
; Script management uses two major segments: Locked, which marks text
; which has been sent to the proof assistant and cannot be altered
; without being retracted, and Queue, which contains stuff being
; queued for processing.  proof-action-list contains a list of
; (span,command,action) triples. The loop looks like: Execute the
; command, and if it's successful, do action on span.  If the
; command's not successful, we bounce the rest of the queue and do
; some error processing.
;
; when a span has been processed, we classify it as follows:
; 'goalsave - denoting a 'goalsave pair in the locked region
;    a 'goalsave region has a 'name property which is the name of the goal
; 'comment - denoting a comment
; 'pbp - denoting a span created by pbp
; 'vanilla - denoting any other span.
;   'pbp & 'vanilla spans have a property 'cmd, which says what
;   command they contain. 

; We don't allow commands while the queue has anything in it.  So we
; do configuration by concatenating the config command on the front in
; proof-shell-insert

;;         proof-assert-until-point, and various gunk for its       ;;
;;         setup and callback                                       ;;


(defun proof-check-atomic-sequents-lists (span cmd end)
  "Check if CMD is the final command in an ACS.

If CMD is matched by the end regexp in `proof-atomic-sequents-list',
the ACS is marked in the current buffer. If CMD does not match any,
`nil' is returned, otherwise non-nil."
  ;;FIXME tms: needs implementation
  nil)


(defun proof-done-advancing (span)
  "The callback function for assert-until-point."
  ;; FIXME da: if the buffer dies, this function breaks horribly.
  ;; Needs robustifying.
  (let ((end (span-end span)) cmd)
    ;; State of spans after advancing: 
    (proof-set-locked-end end)
    (proof-set-queue-start end)
    (setq cmd (span-property span 'cmd))
    (cond
     ;; Comments just get highlighted
     ((eq (span-property span 'type) 'comment)
      (set-span-property span 'mouse-face 'highlight))
     
     ;; "ACS" for future implementation
     ;; ((proof-check-atomic-sequents-lists span cmd end))

     ;; Save command seen, now we'll amalgamate spans.
     ((and (proof-string-match proof-save-command-regexp cmd)
	    (funcall proof-really-save-command-p span cmd))

      (let (nam gspan next)
	;; First, clear the proof completed flag
	(setq proof-shell-proof-completed nil)

	;; Try to set the name of the theorem from the save
	(and proof-save-with-hole-regexp
	     (proof-string-match proof-save-with-hole-regexp cmd)
	     (setq nam (match-string 2 cmd)))

	;; Search backwards for first goal command, 
	;; deleting spans along the way.
	;; (FIXME da: what happens if no goal is found?)
	(setq gspan span)
	(while (or (eq (span-property gspan 'type) 'comment)
		   (not (funcall proof-goal-command-p 
				 (setq cmd (span-property gspan 'cmd)))))
	  (setq next (prev-span gspan 'type))
	  (delete-span gspan)
	  (setq gspan next))

	;; If the name isn't set, try to set it from the goal. 
	(unless nam
	  (and proof-goal-with-hole-regexp
	       (proof-string-match proof-goal-with-hole-regexp
				   (span-property gspan 'cmd))
	       (setq nam (match-string 2 (span-property gspan 'cmd)))))
	;; As a final desparate attempt, set the name to "Unnamed_thm".
	;; FIXME da: maybe this should be prover specific: is
	;; "Unnamed_thm" actually a Coq identifier?
	(unless nam
	  (setq nam proof-unnamed-theorem-name))

	;; Now make the new goal-save span
	(set-span-end gspan end)
	(set-span-property gspan 'mouse-face 'highlight)
	(set-span-property gspan 'type 'goalsave)
	(set-span-property gspan 'name nam)
	
	;; In Coq, we have the invariant that if we've done a save and
	;; there's a top-level declaration then it must be the
	;; associated goal.  (Notice that because it's a callback it
	;; must have been approved by the theorem prover.)
	(and proof-lift-global
	     (funcall proof-lift-global gspan))))

     ;; Goal command just processed, no nested goals allowed.
     ;; We make a fake goal-save from any previous 
     ;; goal to the command before the present one.
     ;; (This is a hack for Isabelle to allow smooth
     ;; undoing in proofs which have no "qed" statements).
     ;; FIXME: abstract common part of this case and case above,
     ;; to improve code by making a useful subroutine.
     ((and (not proof-nested-goals-allowed)
	   (funcall proof-goal-command-p cmd))
      (let (nam gspan hitsave dels)
	;; A preliminary search backwards to 
	;; see if we can find a previous goal before
	;; a save or the start of the buffer.
	(setq gspan (prev-span span 'type))
	(while 
	    (and 
	     gspan
	     (or 
	      (eq (span-property gspan 'type) 'comment)
	      (and
	       (not (funcall proof-goal-command-p 
			     (setq cmd (span-property gspan 'cmd))))
	       (not
		(and (proof-string-match proof-save-command-regexp cmd)
		     (funcall proof-really-save-command-p span cmd)
		     (setq hitsave t))))))
	  (setq dels (cons gspan dels))
	  (setq gspan (prev-span gspan 'type)))
	(unless (or hitsave (null gspan))
	  ;; If we haven't hit a save or the start of the buffer,
	  ;; we make a fake goal-save region.

	  ;; Delete spans between the previous goal and new goal
	  (mapcar 'delete-span dels)

	  ;; Try to set a name from the goal
	  ;; (useless for Isabelle)
	  (and proof-goal-with-hole-regexp
	       (proof-string-match proof-goal-with-hole-regexp
				   (span-property gspan 'cmd))
	       (setq nam (match-string 2 (span-property gspan 'cmd))))
	  ;; As a final desparate attempt, set the name to "Unnamed_thm".
	  (unless nam
	    (setq nam proof-unnamed-theorem-name))
	  
	  ;; Now make the new goal-save span
	  (set-span-end gspan (span-start span))
	  (set-span-property gspan 'mouse-face 'highlight)
	  (set-span-property gspan 'type 'goalsave)
	  (set-span-property gspan 'name nam)))
	;; Finally, do the usual thing with highlighting.
	;; Don't bother with Coq's lift global stuff, we assume
	;; this code is only good for non-nested goals.
	(set-span-property span 'mouse-face 'highlight))
     ;; 
     ;; Otherwise, some other kind of command (or a nested goal).
     (t
      (set-span-property span 'mouse-face 'highlight)
      (and proof-global-p 
	   (funcall proof-global-p cmd)
	   proof-lift-global
	   (funcall proof-lift-global span)))))

  ;; State of scripting may have changed now
  (run-hooks 'proof-state-change-hook))


;; FIXME da: Below it would probably be faster to use the primitive
;; skip-chars-forward rather than scanning character-by-character 
;; with a lisp loop over the whole region. Also I'm not convinced that
;; Emacs should be better at skipping whitespace and comments than the
;; proof process itself!

;; FIXME da: this annoyingly slow even in a buffer only several
;; hundred lines long, even when compiled.

;; FIXME da: using the family of functions buffer-syntactic-context-*
;; may be helpful here.

(defun proof-segment-up-to (pos &optional next-command-end)
  "Create a list of (type,int,string) tuples from end of queue/locked region to POS.
Each tuple denotes the command and the position of its terminator,
type is one of 'comment, or 'cmd. 'unclosed-comment may be consed onto
the start if the segment finishes with an unclosed comment.
If optional NEXT-COMMAND-END is non-nil, we contine past POS until
the next command end."
  (save-excursion
      ;; depth marks number of nested comments.
      ;; quote-parity is false if we're inside quotes.
      ;; Only one of (depth > 0) and (not quote-parity)
      ;; should be true at once. -- hhg
    (let* ((start	(proof-queue-or-locked-end))
	   (str		(make-string (- (buffer-size) start -10) ?x))
	   (i 0) (depth 0) (quote-parity t) done alist c
	  (comment-end-regexp (regexp-quote proof-comment-end))
	  (comment-start-regexp (regexp-quote proof-comment-start)))
	  ;; For forthcoming improvements: skip over boring
	  ;; characters, calculate strings with buffer-substring
	  ;; rather than character at a time.
	  ; (interesting-chars
	  ; (concat (substring proof-comment-start 1 1)
	  ;	   (substring proof-comment-end 1 1)
	  ;	   (char-to-string proof-terminal-char)
	  ;	   "\"")))
      (goto-char start)
     (while (not done)
       (cond
	;; Case 1. We've reached POS, not allowed to go past it,
	;; and are inside a comment
	((and (not next-command-end) (= (point) pos) (> depth 0))
	 (setq done t alist (cons 'unclosed-comment alist)))
	;; Case 2. We've reached the end of the buffer while
	;; scanning inside a comment or string
	((= (point) (point-max))
	 (cond
	  ((not quote-parity)
	   (message "Warning: unclosed quote"))
	  ((> depth 0)
	   (setq done t alist (cons 'unclosed-comment alist))))
	 (setq done t))
	;; Case 3. Found a comment end, not inside a string
	((and (looking-at comment-end-regexp) quote-parity)
	 (if (= depth 0) 
	     (progn
	       (message "Warning: extraneous comment end")
	       (setq done t))
	   (setq depth (- depth 1))
	   (forward-char (length (match-string 0)))
	   (if (eq i 0) 
	       (setq alist (cons (list 'comment "" (point)) alist))
	     (aset str i ?\ )
	     (incf i))))
	;; Case 4. Found a comment start, not inside a string
	((and (looking-at comment-start-regexp) quote-parity)
	 (setq depth (+ depth 1))
	 (forward-char (length (match-string 0))))
	;; Case 5. Inside a comment. 
	((> depth 0)
	 (forward-char))
	;; Case 6. Anything else
	(t
	 ;; Skip whitespace before the start of a command, otherwise
	 ;; other characters in the accumulator string str
	 (setq c (char-after (point)))
	 (if (or (> i 0) (not (= (char-syntax c) ?\ )))
	     (progn
	       (aset str i c)
	       (incf i)))

	 ;; Maintain quote-parity
	 (cond
	  ((and quote-parity (looking-at proof-string-start-regexp))
	   (setq quote-parity nil))
	  ((and (not quote-parity) (looking-at proof-string-end-regexp))
	   (setq quote-parity t)))

	 (forward-char)

	 ;; Found the end of a command
	 (if (and (= c proof-terminal-char) quote-parity)
	     (progn 
	       (setq alist 
		     (cons (list 'cmd (substring str 0 i) (point)) alist))
	       (cond
		((> (point) pos)
		 (setq done t))
		;; FIXME da: This case preserves the old behaviour, but I
		;; think it's wrong: should just have > case above.
		((and (not next-command-end) (= (point) pos))
		 (setq done t))
		(t
		 (setq i 0))))))))
     alist)))

(defun proof-semis-to-vanillas (semis &optional callback-fn)
  "Convert a sequence of terminator positions to a set of vanilla extents.
Proof terminator positions SEMIS has the form returned by
the function proof-segment-up-to."
  (let ((ct (proof-unprocessed-begin)) span alist semi)
    (while (not (null semis))
      (setq semi (car semis)
            span (make-span ct (nth 2 semi))
	    ct (nth 2 semi))
      (if (eq (car (car semis)) 'cmd)
	  (progn
	    (set-span-property span 'type 'vanilla)
	    (set-span-property span 'cmd (nth 1 semi))
	    (setq alist (cons (list span (nth 1 semi) 
				    (or callback-fn 'proof-done-advancing))
			      alist)))
	(set-span-property span 'type 'comment)
	(setq alist (cons (list span proof-no-command 'proof-done-advancing) 
			  alist)))
	(setq semis (cdr semis)))
    (nreverse alist)))

;;
;; Two commands for moving forwards in proof scripts.
;; Moving forward for a "new" command may insert spaces
;; or new lines.  Moving forward for the "next" command
;; does not.
;;

(defun proof-script-new-command-advance ()
  "Move point to a nice position for a new command.
Assumes that point is at the end of a command."
  (interactive)
  (if proof-one-command-per-line
      ;; One command per line: move to next new line,
      ;; creating one if at end of buffer or at the
      ;; start of a blank line.  (This has the pleasing
      ;; effect that blank regions of the buffer are
      ;; automatically extended when inserting new commands).
      (cond
       ((eq (forward-line) 1)
	(newline))
       ((eolp)
        (newline)
	(forward-line -1)))
    ;; Multiple commands per line: skip spaces at point,
    ;; and insert the same number of spaces that were
    ;; skipped in front of point (at least one).
    ;; This has the pleasing effect that the spacing
    ;; policy of the current line is copied: e.g.
    ;;   <command>;  <command>;
    ;; Tab columns don't work properly, however.
    ;; Instead of proof-one-command-per-line we could
    ;; introduce a "proof-command-separator" to improve
    ;; this.
    (let ((newspace (max (skip-chars-forward " \t") 1))
	  (p (point)))
	(insert-char ?\ newspace)
	(goto-char p))))

(defun proof-script-next-command-advance ()
  "Move point to the beginning of the next command if it's nearby.
Assumes that point is at the end of a command."
  (interactive)
  ;; skip whitespace on this line
  (skip-chars-forward " \t")		
  (if (and proof-one-command-per-line (eolp))
      ;; go to the next line if we have one command per line
      (forward-line)))


(defun proof-assert-until-point-interactive ()
  "Process the region from the end of the locked-region until point.
Default action if inside a comment is just process as far as the start of
the comment."
  (interactive)
  (proof-assert-until-point))


; Assert until point - We actually use this to implement the 
; assert-until-point, active terminator keypress, and find-next-terminator. 
; In different cases we want different things, but usually the information
; (i.e. are we inside a comment) isn't available until we've actually run
; proof-segment-up-to (point), hence all the different options when we've
; done so.

;; FIXME da: this command doesn't behave as the doc string says when
;; inside comments.  Also is unhelpful at the start of commands, and
;; in the locked region.  I prefer the new version below.

(defun proof-assert-until-point
  (&optional unclosed-comment-fun ignore-proof-process-p)
  "Process the region from the end of the locked-region until point.
Default action if inside a comment is just process as far as the start of
the comment. 

If you want something different, put it inside
UNCLOSED-COMMENT-FUN. If IGNORE-PROOF-PROCESS-P is set, no commands
will be added to the queue and the buffer will not be activated for
scripting."
  (unless ignore-proof-process-p 
    (proof-activate-scripting nil 'advancing))
  (let ((semis))
    (save-excursion
      ;; Give error if no non-whitespace between point and end of locked region.
      ;; FIXME da: a nasty mess
      ;; FIXME: this test meaningful for assert *exactly* to point, not
      ;; when we assert to next command beyond point.
      (if (proof-only-whitespace-to-locked-region-p)
	  (error "There's nothing to do to!"))
      ;; NB: (point) has now been moved backwards to first non-whitespace char.
      (setq semis (proof-segment-up-to (point))))
    (if (and unclosed-comment-fun (eq 'unclosed-comment (car semis)))
	(funcall unclosed-comment-fun)
      (if (eq 'unclosed-comment (car semis)) (setq semis (cdr semis)))
      (if (and (not ignore-proof-process-p) (null semis))
	  (error "I can't find any complete commands to process!"))
      (goto-char (nth 2 (car semis)))
      (and (not ignore-proof-process-p)
	   (let ((vanillas (proof-semis-to-vanillas (nreverse semis))))
	     (proof-extend-queue (point) vanillas))))))


;; da: This is my alternative version of the above.
;; It works from the locked region too.
;; I find it more convenient to assert up to the current command (command
;; point is inside), and move to the next command.
;; This means proofs can be easily replayed with point at the start
;; of lines.  Above function gives stupid "nothing to do error." when
;; point is on the start of line or in the locked region.

;; FIXME: behaviour inside comments may be odd at the moment.  (it
;; doesn't behave as docstring suggests, same prob as
;; proof-assert-until-point)
;; FIXME: polish the undo behaviour and quit behaviour of this
;; command (should inhibit quit somewhere or other).

(defun proof-assert-next-command-interactive ()
  "Process until the end of the next unprocessed command after point.
If inside a comment, just process until the start of the comment."
  (interactive)
  (proof-assert-next-command))
  
(defun proof-assert-next-command
  (&optional unclosed-comment-fun ignore-proof-process-p
	     dont-move-forward for-new-command)
  "Process until the end of the next unprocessed command after point.
If inside a comment, just process until the start of the comment.  

If you want something different, put it inside UNCLOSED-COMMENT-FUN. 
If IGNORE-PROOF-PROCESS-P is set, no commands will be added to the queue.
Afterwards, move forward to near the next command afterwards, unless
DONT-MOVE-FORWARD is non-nil.  If FOR-NEW-COMMAND is non-nil,
a space or newline will be inserted automatically."
  (unless ignore-proof-process-p
    (proof-activate-scripting nil 'advancing))
  (or ignore-proof-process-p
      (if (proof-locked-region-full-p)
	  (error "Locked region is full, no more commands to do!")))
  (let ((semis))
    (save-excursion
      ;; CHANGE from old proof-assert-until-point: don't bother check
      ;; for non-whitespace between locked region and point.
      ;; CHANGE: ask proof-segment-up-to to scan until command end
      ;; (which it used to do anyway, except in the case of a comment)
      (setq semis (proof-segment-up-to (point) t)))
    ;; old code:
    ;;(if (not (re-search-backward "\\S-" (proof-unprocessed-begin) t))
    ;;	  (progn (goto-char pt)
    ;;       (error "I don't know what I should be doing in this buffer!")))
    ;; (setq semis (proof-segment-up-to (point))))
    (if (and unclosed-comment-fun (eq 'unclosed-comment (car-safe semis)))
	(funcall unclosed-comment-fun)
      (if (eq 'unclosed-comment (car-safe semis))
	  (setq semis (cdr semis)))
      (if (and (not ignore-proof-process-p) (null semis))
	  (error "I can't see any complete commands to process!"))
      (goto-char (nth 2 (car semis)))
      (if (not ignore-proof-process-p)
	   (let ((vanillas (proof-semis-to-vanillas (nreverse semis))))
;	     (if crowbar (setq vanillas (cons crowbar vanillas)))
	     (proof-extend-queue (point) vanillas)))
      ;; This is done after the queuing to be polite: it means the
      ;; spacing policy enforced here is not put into the locked
      ;; region so the user can re-edit.
      (if (not dont-move-forward)
	   (if for-new-command
	       (proof-script-new-command-advance)
	     (proof-script-next-command-advance))))))

;;         insert-pbp-command - an advancing command, for use when  ;;
;;         PbpHyp or Pbp has executed in LEGO, and returned a       ;;
;;         command for us to run                                    ;;

(defun proof-insert-pbp-command (cmd)
  (proof-activate-scripting)
  (let (span)
    (proof-goto-end-of-locked)
    (insert cmd)
    (setq span (make-span (proof-locked-end) (point)))
    (set-span-property span 'type 'pbp)
    (set-span-property span 'cmd cmd)
    (proof-start-queue (proof-unprocessed-begin) (point) 
		       (list (list span cmd 'proof-done-advancing)))))


;;         proof-retract-until-point and associated gunk            ;;
;;         most of the hard work (i.e computing the commands to do  ;;
;;         the retraction) is implemented in the customisation      ;;
;;         module (lego.el or coq.el) which is why this looks so    ;;
;;         straightforward                                          ;;


(defun proof-done-retracting (span)
  "Update display after proof process has reset its state.
See also the documentation for `proof-retract-until-point'.
Optionally delete the region corresponding to the proof sequence."
  ;; 10.9.99: da: added this line so that undo always clears the
  ;; proof completed flag.  Rationale is that undoing never leaves
  ;; prover in a "proof just completed" state.
  (setq proof-shell-proof-completed nil)
  (if (span-live-p span)
      (let ((start (span-start span))
	    (end (span-end span))
	    (kill (span-property span 'delete-me)))
	;; FIXME: why is this test for an empty locked region here?
	;; seems it could prevent the queue and locked regions
 	;; from being detached.  Not sure where they are supposed
 	;; to be detached from buffer, but following calls would
 	;; do the trick if necessary.
	(unless (proof-locked-region-empty-p)
	  (proof-set-locked-end start)
	  (proof-set-queue-end start))
	(delete-spans start end 'type)
	(delete-span span)
	(if kill (kill-region start end))))
  ;; State of scripting may have changed now
  (run-hooks 'proof-state-change-hook))

(defun proof-setup-retract-action (start end proof-command delete-region)
  (let ((span (make-span start end)))
    (set-span-property span 'delete-me delete-region)
    (list (list span proof-command 'proof-done-retracting))))


(defun proof-last-goal-or-goalsave ()
  (save-excursion
    (let ((span (span-at-before (proof-locked-end) 'type)))
    (while (and span 
		(not (eq (span-property span 'type) 'goalsave))
		(or (eq (span-property span 'type) 'comment)
		    (not (funcall proof-goal-command-p
				       (span-property span 'cmd)))))
      (setq span (prev-span span 'type)))
    span)))

(defun proof-retract-target (target delete-region)
  "Retract the span TARGET and delete it if DELETE-REGION is non-nil.
Notice that this necessitates retracting any spans following TARGET,
up to the end of the locked region."
  (let ((end   (proof-unprocessed-begin))
	(start (span-start target))
	(span  (proof-last-goal-or-goalsave))
	actions)

    ;; Examine the last span in the locked region.  
    
    ;; If the last goal or save span is not a goalsave (i.e. it's
    ;; open) we examine to see how to remove it
    (if (and span (not (eq (span-property span 'type) 'goalsave)))
	;; If the goal or goalsave span ends before the target span,
	;; then we are retracting within the last unclosed proof,
	;; and the retraction just amounts to a number of undo
	;; steps.  
	;; FIXME: really, there shouldn't be more work to do: so
	;;  why call proof-find-and-forget-fn later?
	(if (< (span-end span) (span-end target))
	    (progn
	      ;; Skip comment spans at and immediately following target
	      (setq span target)
	      (while (and span (eq (span-property span 'type) 'comment))
		(setq span (next-span span 'type)))
	      ;; Calculate undos for the current open segment
	      ;; of proof commands
	      (setq actions (proof-setup-retract-action
			     start end 
			     (if (null span) proof-no-command
			       (funcall proof-count-undos-fn span))
			     delete-region)
		    end start))
	  ;; Otherwise, start the retraction by killing off the
	  ;; currently active goal.
	  ;; FIXME: and couldn't we move the end upwards?
	  (setq actions 
		(proof-setup-retract-action (span-start span) end
					    proof-kill-goal-command
						    delete-region)
		end (span-start span))))
    ;; Check the start of the target span lies before the end
    ;; of the locked region (should always be true since we don't
    ;; make spans outside the locked region at the moment)...
    (if (> end start) 
	(setq actions
	      ;; Append a retract action to clear the entire
	      ;; start-end region.  Rely on proof-find-and-forget-fn
	      ;; to calculate a command which "forgets" back to
	      ;; the first definition, declaration, or whatever
	      ;; that comes after the target span.
	      ;; FIXME: originally this assumed a linear context, 
	      ;; and that forgetting the first thing  forgets all 
	      ;; subsequent ones.  it might be more general to 
	      ;; allow *several* commands, and even queue these
	      ;; separately for each of the spans following target
	      ;; which are concerned.
	      (nconc actions (proof-setup-retract-action 
			      start end
			      (funcall proof-find-and-forget-fn target)
			      delete-region))))
      
    (proof-start-queue (min start end) (proof-locked-end) actions)))

;; FIXME da:  I would rather that this function moved point to
;; the start of the region retracted?

;; FIXME da: Maybe retraction to the start of
;; a file should remove it from the list of included files?
(defun proof-retract-until-point-interactive (&optional delete-region)
  "Tell the proof process to retract until point.
If invoked outside a locked region, undo the last successfully processed
command.  If called with a prefix argument (DELETE-REGION non-nil), also
delete the retracted region from the proof-script."
  (interactive "P")
  (proof-retract-until-point delete-region))

(defun proof-retract-until-point (&optional delete-region)
  "Set up the proof process for retracting until point.
In particular, set a flag for the filter process to call 
`proof-done-retracting' after the proof process has successfully 
reset its state.
If DELETE-REGION is non-nil, delete the region in the proof script
corresponding to the proof command sequence.
If invoked outside a locked region, undo the last successfully processed
command."
  ;; Make sure we're ready
  ;; FIXME: next step in extend regions: (proof-activate-scripting nil 'retracting)
  (proof-activate-scripting)
  (let ((span (span-at (point) 'type)))
    ;; FIXME da: shouldn't this test be earlier??
    (if (proof-locked-region-empty-p)
	(error "No locked region"))
    ;; FIXME da: rationalize this: it retracts the last span
    ;; in the buffer if there was no span at point, right?
    ;; why?
    (and (null span)
	 (progn 
	   (proof-goto-end-of-locked) 
	   (backward-char)
	   (setq span (span-at (point) 'type))))
    (proof-retract-target span delete-region)))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;         misc other user functions                                ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; FIXME: it turns out that this function is identical to the one below.
(defun proof-undo-last-successful-command-interactive (delete)
  "Undo last successful command at end of locked region.
If DELETE argument is set (called with a prefix argument), 
the text is also deleted from the proof script."
  (interactive "P")
  (proof-undo-last-successful-command (not delete)))

(defun proof-undo-last-successful-command (&optional no-delete)
  "Undo last successful command at end of locked region.
Unless optional NO-DELETE is set, the text is also deleted from
the proof script."
  (unless (proof-locked-region-empty-p)
    (let ((lastspan (span-at-before (proof-locked-end) 'type)))
      (if lastspan
	  (progn
	    (goto-char (span-start lastspan))
	    (proof-retract-until-point (not no-delete)))
	(error "Nothing to undo!")))))


;; FIXME da: need to add some way of recovery here.  Perhaps
;; query process as to its state as well.  Also unwind protects
;; here.

;; FIXME da: this probably belongs in proof-shell, as do
;; some of the following functions.

(defun proof-interrupt-process ()
  "Interrupt the proof assistant.  Warning! This may confuse Proof General."
  (interactive)
  (unless (proof-shell-live-buffer)
      (error "Proof Process Not Started!"))
  (unless proof-shell-busy
    (error "Proof Process Not Active!"))
  (with-current-buffer proof-shell-buffer
    (comint-interrupt-subjob)))
  
    
(defun proof-find-next-terminator ()
  "Set point after next `proof-terminal-char'."
  (interactive)
  (let ((cmd (span-at (point) 'type)))
    (if cmd (goto-char (span-end cmd))
;      (and (re-search-forward "\\S-" nil t)
;	   (proof-assert-until-point nil 'ignore-proof-process)))))
      (proof-assert-next-command nil 'ignore-proof-process))))

(defun proof-goto-command-start ()
  "Move point to start of current command."
  (interactive)
  (let ((cmd (span-at (point) 'type)))
    (if cmd (goto-char (span-start cmd)) ; BUG: only works for unclosed proofs.
      (let ((semis (proof-segment-up-to (point) t)))
	(if (eq 'unclosed-comment (car semis)) (setq semis (cdr semis)))
	(if (and semis (car semis) (car (car semis)))
	    (progn
	      (goto-char (nth 2 (car (car semis))))
	      (skip-chars-forward " \t\n")))))))

(defun proof-process-buffer ()
  "Process the current buffer and set point at the end of the buffer."
  (interactive)
  (goto-char (point-max))
  (proof-assert-until-point-interactive))

(defun proof-retract-buffer ()
  "Retract the current buffer and set point at the start of the buffer."
  (interactive)
  (goto-char (point-min))
  (proof-retract-until-point-interactive))



;; FIXME da: this could do with some tweaking.  Be careful to
;; avoid memory leaks.  If a buffer is killed and it's local
;; variables are, then so should all the spans which were allocated
;; for that buffer.  Is this what happens?  By garbage collection?
;; Otherwise we should perhaps *delete* spans corresponding to 
;; the locked and queue regions as well as the others.
(defun proof-restart-buffers (buffers)
  "Remove all extents in BUFFERS and maybe reset `proof-script-buffer'.
No effect on a buffer which is nil or killed.  If one of the buffers
is the current scripting buffer, then proof-script-buffer 
will deactivated."
  (mapcar
   (lambda (buffer)
     (save-excursion
       (if (buffer-live-p buffer)
	   (with-current-buffer buffer
	     (if proof-active-buffer-fake-minor-mode
		 (setq proof-active-buffer-fake-minor-mode nil))
	     (delete-spans (point-min) (point-max) 'type)
	     (proof-detach-segments buffer)
	     ;; 29.9.99. Added next line to allow useful toggling
	     ;; of strict-read-only during a session.
	     (proof-init-segmentation)))
       (if (eq buffer proof-script-buffer)
	   (setq proof-script-buffer nil))))
   buffers))

(defun proof-script-buffers-with-spans ()
  "Return a list of all buffers with spans.
This is calculated by finding all the buffers with a non-nil
value of proof-locked span."
  (let ((bufs-left (buffer-list)) 
	bufs-got)
    (dolist (buf bufs-left bufs-got)
      (if (with-current-buffer buf proof-locked-span)
	  (setq bufs-got (cons buf bufs-got))))))

(defun proof-script-remove-all-spans-and-deactivate ()
  "Remove all spans from scripting buffers via proof-restart-buffers."
  (proof-restart-buffers (proof-script-buffers-with-spans)))


;; A command for making things go horribly wrong - it moves the
;; end-of-locked-region marker backwards, so user had better move it
;; correctly to sync with the proof state, or things will go all
;; pear-shaped.

(defun proof-frob-locked-end ()
  (interactive)
  "Move the end of the locked region backwards. 
Only for use by consenting adults."
  (cond
   ((not (eq (current-buffer) proof-script-buffer))
    (error "Not in active scripting buffer"))
   ((> (point) (proof-locked-end))
    (error "Can only move backwards"))
   (t (proof-set-locked-end (point))
      (delete-spans (proof-locked-end) (point-max) 'type))))

(defvar proof-minibuffer-history nil
  "History of proof commands read from the minibuffer")

(defun proof-execute-minibuffer-cmd ()
  "Prompt for a command in the minibuffer and send it to proof assistant.
The command isn't added to the locked region.

If proof-state-preserving-p is configured, it is used as a check
that the command will be safe to execute, in other words, that
it won't ruin synchronization.  If applied to the command it 
returns false, then an error message is given."
  (interactive)
  (let (cmd)
    ;; FIXME note: removed ready-prover call since it's done by
    ;; proof-shell-invisible-command anyway.
    ;; (proof-shell-ready-prover)
    ;; was (proof-check-process-available 'relaxed) 
    (setq cmd (read-string "Command: " nil 'proof-minibuffer-history))
    (if (and
	 proof-state-preserving-p
	 (not (funcall proof-state-preserving-p cmd)))
	  (error "Command is not state preserving, I won't execute it!"))
    (proof-shell-invisible-command 
     (if proof-terminal-string
	 (concat cmd proof-terminal-string)
       cmd))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; command history  (unfinished)
;;
;; da: below functions for input history simulation are quick hacks.
;; Could certainly be made more efficient.

;(defvar proof-command-history nil
;  "History used by proof-previous-matching-command and friends.")

;(defun proof-build-command-history ()
;  "Construct proof-command-history from script buffer.
;Based on position of point."
;  ;; let
;  )

;(defun proof-previous-matching-command (arg)
;  "Search through previous commands for new command matching current input."
;  (interactive))
;  ;;(if (not (memq last-command '(proof-previous-matching-command
;  ;; proof-next-matching-command)))
;      ;; Start a new search
      
;(defun proof-next-matching-command (arg)
;  "Search through following commands for new command matching current input."
;  (interactive "p")
;  (proof-previous-matching-command (- arg)))

;;
;; end command history stuff
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	  



;;; 
;;; User-level commands invoking common commands for
;;; the underlying proof assistant.
;;;

;;; These are based on defcustom'd settings so that users may 
;;; re-configure the system to their liking.


;; FIXME: da: add more general function for inserting into the
;; script buffer and the proof process together, and using
;; a choice of minibuffer prompting (hated by power users, perfect
;; for novices).
;; TODO:
;;   Add named goals.
;;   Coherent policy for movement here and elsewhere based on
;;    proof-one-command-per-line user option.
;;   Coherent policy for sending to process after writing into
;;    script buffer.  Could have one without the other.
;;    For example, may be more easy to edit complex goal string
;;    first in the script buffer.  Ditto for tactics, etc.



;;; FIXME: should move these to a new file, not really scripting
;;; related.

;;; FIXME: rationalize use of terminator string (i.e. remove
;;; it below, add it to each instance for consistency).


;;
;; Helper macros and functions
;;

;; See put expression at end to give this indentation like while form
(defmacro proof-if-setting-configured (var &rest body)
  "Give error if a configuration setting VAR is unset, otherwise eval BODY."
  `(if ,var
       (progn ,@body)
     (error "Proof General not configured for this: set %s" 
	    ,(symbol-name var))))

(defmacro proof-define-assistant-command (fn doc cmdvar &optional body)
  "Define command FN to send string BODY to proof assistant, based on CMDVAR.
BODY defaults to CMDVAR, a variable."
  `(defun ,fn ()
     ,(concat doc 
	      (concat "\nIssues a command to the assistant based on " 
		      (symbol-name cmdvar) ".") 
		"")
     (interactive)
     (proof-if-setting-configured ,cmdvar
       (proof-shell-invisible-command
	(concat ,(or body cmdvar) proof-terminal-string)))))

(defmacro proof-define-assistant-command-witharg (fn doc cmdvar prompt &rest body)
  "Define command FN to prompt for string CMDVAR to proof assistant.
CMDVAR is a function or string.  Automatically has history."
  `(progn
     (defvar ,(intern (concat (symbol-name fn) "-history")) nil
       ,(concat "History of arguments for " (symbol-name fn) "."))
     (defun ,fn (arg)
     ,(concat doc "\nIssues a command based on ARG to the assistant, using " 
	      (symbol-name cmdvar) ".\n"
	      "The user is prompted for an argument.")
      (interactive
       (proof-if-setting-configured ,cmdvar
	   (if (stringp ,cmdvar)
	       (list (format ,cmdvar
		 	 (read-string 
			   ,(concat prompt ": ") ""
			   ,(intern (concat (symbol-name fn) "-history")))))
	     (funcall ,cmdvar))))
       ,@body)))

(defun proof-issue-new-command (cmd)
  "Insert CMD into the script buffer and issue it to the proof assistant.
If point is in the locked region, move to the end of it first.
Start up the proof assistant if necessary."
  ;; FIXME: da: I think we need a (proof-script-switch-to-buffer)
  ;; function (so there is some control over display).
  ;; (switch-to-buffer proof-script-buffer)
  (if (proof-shell-live-buffer)
      (if (proof-in-locked-region-p)
	  (proof-goto-end-of-locked-interactive)))
  (proof-script-new-command-advance)
  ;; FIXME: fixup behaviour of undo here.  Really want
  ;; to temporarily disable undo for insertion.
  ;; (buffer-disable-undo) this trashes whole undo list!
  (insert cmd)
  ;; FIXME: could do proof-indent-line here, but let's
  ;; wait until indentation is fixed.
  (proof-assert-until-point-interactive))

;;
;; Commands which do not require a prompt and send an invisible command.
;;

(proof-define-assistant-command proof-prf  
  "Show the current proof state."
  proof-showproof-command)
(proof-define-assistant-command proof-ctxt 
  "Show the current context."
  proof-context-command)
(proof-define-assistant-command proof-help 
  "Show a help or information message from the proof assistant.
Typically, a list of syntax of commands available."
  proof-info-command)
(proof-define-assistant-command proof-cd
  "Change directory to the default directory for the current buffer."
  proof-shell-cd-cmd
  (format proof-shell-cd-cmd
	  ;; Use expand-file-name to avoid problems with dumb
	  ;; proof assistants and "~"
	  (expand-file-name (default-directory))))

(defun proof-cd-sync ()
  "If proof-shell-cd-cmd is set, do proof-cd and wait for prover ready.
This is intended as a value for proof-activate-scripting-hook"
  ;; The hook is set in proof-mode before proof-shell-cd-cmd may be set,
  ;; so we explicitly test it here.  
  (if proof-shell-cd-cmd 
      (progn
	(proof-cd)
	(proof-shell-wait))))

;;
;; Commands which require an argument, and maybe affect the script.
;;

(proof-define-assistant-command-witharg proof-find-theorems
 "Search for items containing given constants."
 proof-find-theorems-command
 "Find theorems containing the constant(s)"
 (proof-shell-invisible-command arg))

(proof-define-assistant-command-witharg proof-issue-goal
 "Write a goal command in the script, prompting for the goal."
 proof-goal-command
 "Goal"
 (let ((proof-one-command-per-line t))   ; Goals always start at a new line
   (proof-issue-new-command arg)))

(proof-define-assistant-command-witharg proof-issue-save 
 "Write a save/qed command in the script, prompting for the theorem name."
 proof-save-command
 "Save as"
 (let ((proof-one-command-per-line t))   ; Saves always start at a new line
   (proof-issue-new-command arg)))



;;;
;;; Definition of Menus
;;;

;;; A handy utility function used in buffer menu.
(defun proof-switch-to-buffer (buf &optional noselect)
  "Switch to or display buffer BUF in other window unless already displayed.
If optional arg NOSELECT is true, don't switch, only display it.
No action if BUF is nil."
  ;; Maybe this needs to be more sophisticated, using 
  ;; proof-display-and-keep-buffer ?
  (and buf
       (unless (eq buf (window-buffer (selected-window)))
	 (if noselect
	     (display-buffer buf t)
	   (switch-to-buffer-other-window buf)))))

(defvar proof-help-menu
  `("Help"
    [,(concat proof-assistant " web page")
     (browse-url proof-assistant-home-page) t]
    ["Proof General home page"
     (browse-url proof-general-home-page) t]
    ["Proof General Info"
     (info "ProofGeneral") t]
    )
  "Proof General help menu.")

(defvar proof-buffer-menu
  '("Buffers"
    ["Active scripting"
     (proof-switch-to-buffer proof-script-buffer)
     :active (buffer-live-p proof-script-buffer)]
    ["Goals"
     (proof-switch-to-buffer proof-goals-buffer t)
     :active (buffer-live-p proof-goals-buffer)]
    ["Response"
     (proof-switch-to-buffer proof-response-buffer t)
     :active (buffer-live-p proof-response-buffer)]
    ["Shell"
     (proof-switch-to-buffer proof-shell-buffer)
     :active (buffer-live-p proof-shell-buffer)])
  "Proof General buffer menu.")

;; FIXME da: could move this elsewhere.  
;; FIXME da: rationalize toolbar menu items with this menu, i.e.
;; remove common stuff.
(defvar proof-shared-menu
  (append
    (list
;     ["Display proof state"
;      proof-prf
;      :active (proof-shell-live-buffer)]
;     ["Display context"
;      proof-ctxt
;      :active (proof-shell-live-buffer)]
;     ["Find theorems"
;      proof-find-theorems
;      :active (proof-shell-live-buffer)]
     ["Start proof assistant"
      proof-shell-start
      :active (not (proof-shell-live-buffer))]
     ["Toggle scripting"
      proof-toggle-active-scripting
      :active t]
;     ["Restart scripting"
;      proof-shell-restart
;      :active (proof-shell-live-buffer)]
     ["Exit proof assistant"
      proof-shell-exit
      :active (proof-shell-live-buffer)])
    (list proof-help-menu)
    (list proof-buffer-menu)
    ;; Would be nicer to put this at the bottom, but it's
    ;; a bit tricky then to get it in all menus.
    ;; UGLY COMPATIBILITY  FIXME: remove this soon
    (list (if (string-match "XEmacs 19.1[2-9]" emacs-version)
	      "--:doubleLine" "----"))
    )
  "Proof General menu for various modes.")

(defvar proof-bug-report-menu
  (append
   ;; UGLY COMPATIBILITY  FIXME: remove this soon
   (list (if (string-match "XEmacs 19.1[2-9]" emacs-version)
	     "--:doubleLine" "----"))
   (list
    ["Submit bug report"
     proof-submit-bug-report
     :active t]))
  "Proof General menu for submitting bug report (one item plus separator).")


(defvar proof-menu  
  (append '(["Active terminator" proof-active-terminator-minor-mode
	     :active t
	     :style toggle
             :selected proof-active-terminator-minor-mode]
	    ["Toolbar" proof-toolbar-toggle
	       :active (featurep 'toolbar)
	       :style toggle
	       :selected (not proof-toolbar-inhibit)]
	    "----")
	  ;; UGLY COMPATIBILITY  FIXME: remove this soon
          (list (if (string-match "XEmacs 19.1[2-9]" emacs-version)
		    "--:doubleLine" "----"))
          proof-shared-menu
          )
  "The menu for the proof assistant.")



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;          Active terminator minor mode                            ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; FIXME: Paul Callaghan wants to make the default for this be
;; 't'.  Perhaps we need a user option which configures the default.
;; Moreover, this minor mode is only relevant to scripting
;; buffers, so a buffer-local setting may be inappropriate.
(deflocal proof-active-terminator-minor-mode nil 
  "Active terminator minor mode flag")

;; Make sure proof-active-terminator-minor-mode is registered
(or (assq 'proof-active-terminator-minor-mode minor-mode-alist)
    (setq minor-mode-alist
	  (append minor-mode-alist
		  (list '(proof-active-terminator-minor-mode
			  (concat " " proof-terminal-string))))))

(defun proof-active-terminator-minor-mode (&optional arg)
  "Toggle Proof General's active terminator minor mode.
With ARG, turn on the Active Terminator minor mode if and only if ARG
is positive.

If active terminator mode is enabled, pressing a terminator will 
automatically activate `proof-assert-next-command' for convenience."
 (interactive "P")
 (setq proof-active-terminator-minor-mode
       (if (null arg) (not proof-active-terminator-minor-mode)
	 (> (prefix-numeric-value arg) 0)))
 (if (fboundp 'redraw-modeline)
     (redraw-modeline)
   (force-mode-line-update)))

(defun proof-process-active-terminator ()
  "Insert the proof command terminator, and assert up to it."
  (let ((mrk (point)) ins incomment)
    (if (looking-at "\\s-\\|\\'\\|\\w") 
	(if (proof-only-whitespace-to-locked-region-p)
	    (error "I don't know what I should be doing in this buffer!")))
    (if (not (= (char-after (point)) proof-terminal-char))
	(progn (forward-char) (insert proof-terminal-string) (setq ins t)))
    (proof-assert-until-point
     (function (lambda ()
		 (setq incomment t)
		 (if ins (backward-delete-char 1))
		 (goto-char mrk)
		 (insert proof-terminal-string))))
    (or incomment
	(proof-script-next-command-advance))))

(defun proof-active-terminator ()
  "Insert the terminator, perhaps sending the command to the assistant.
If proof-active-terminator-minor-mode is non-nil, the command will be
sent to the assistant."
  (interactive)
  (if proof-active-terminator-minor-mode 
      (proof-process-active-terminator)
    (self-insert-command 1)))







;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Proof General scripting mode definition			    ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;; da: this isn't so nice if a scripting buffer should inherit
;; from another mode: e.g. for Isabelle, we would like to use
;; sml-mode.
;; FIXME: add more doc to the mode below, to give hints on
;; configuring for new assistants.

;;;###autoload
(eval-and-compile			; to define vars
(define-derived-mode proof-mode fundamental-mode 
  proof-general-name
  "Proof General major mode class for proof scripts.
\\{proof-mode-map}"
  (setq proof-buffer-type 'script)

  ;; We set hook functions here rather than in proof-config-done
  ;; so that they can be adjusted by prover specific code
  ;; if need be.

  (make-local-hook 'kill-buffer-hook)
  (add-hook 'kill-buffer-hook 'proof-script-kill-buffer-fn t t)

  (make-local-hook 'proof-activate-script-hook) ; necessary?
  (add-hook 'proof-activate-scripting-hook 'proof-cd-sync nil t)))

(defun proof-script-kill-buffer-fn ()
  "Value of kill-buffer-hook for proof script buffers.
Clean up before a script buffer is killed.
If killing the active scripting buffer, run proof-deactivate-scripting.
Otherwise just do proof-restart-buffers to delete some spans from memory."
  ;; Deactivate scripting in the current buffer if need be, forcing
  ;; retraction.
  (if (eq (current-buffer) proof-script-buffer)
      (proof-deactivate-scripting 'retract))
  (proof-restart-buffers (list (current-buffer)))
  ;; Hide away goals and response: this is a hack because otherwise
  ;; we can lead the user to frustration with the dedicated windows
  ;; nonsense.
  (if proof-goals-buffer (bury-buffer proof-goals-buffer))
  (if proof-response-buffer (bury-buffer proof-response-buffer)))
  

;; Fixed definitions in proof-mode-map, which don't depend on
;; prover configuration.
;;; INDENT HACK: font-lock only recognizes define-key at start of line
(let ((map proof-mode-map))
(define-key map [(control c) (control e)] 'proof-find-next-terminator)
(define-key map [(control c) (control a)] 'proof-goto-command-start)

;; Sep'99. FIXME: key maps need reorganizing, so do the assert-until style
;; functions.   I've re-bound C-c C-n and C-c C-u to the toolbar functions
;; to make the behaviour the same.  People find the "enhanced" behaviour
;; of the other functions confusing.  Moreover the optional argument
;; to delete is a bad thing for C-c C-u, since repeating it fast will 
;; tend to delete!
(define-key map [(control c) (control n)] 'proof-toolbar-next)
(define-key map [(control c) (control u)] 'proof-toolbar-undo)
(define-key map [(control c) (control b)] 'proof-toolbar-use)

;; newer bindings
(define-key map [(control c) (control r)] 'proof-toolbar-retract)
(define-key map [(control c) (control s)] 'proof-toggle-active-scripting)

;;;; (define-key map [(control c) (control n)] 'proof-assert-next-command-interactive)
;; FIXME : This ought to be set to 'proof-assert-until point
(define-key map [(control c) (return)]	  'proof-assert-next-command-interactive)
;; FIXME: The following two functions should be unified.
(define-key map [(control c) ?u]	  'proof-retract-until-point-interactive)
;;;; (define-key map [(control c) (control u)] 'proof-undo-last-successful-command-interactive)
(define-key map [(control c) ?\']	  'proof-goto-end-of-locked-interactive)
;; FIXME da: this command copies a proof command from within the locked region
;; to the end of it at the moment (contrary to the old name "send", nothing to
;; do with shell).  Perhaps we could define a
;; collection of useful copying functions which do this kind of thing.
(define-key map [(control button1)]	  'proof-mouse-track-insert)
;;; (define-key map [(control c) (control b)] 'proof-process-buffer)

(define-key map [(control c) (control z)] 'proof-frob-locked-end)
(define-key map [(control c) (control p)] 'proof-prf)
(define-key map [(control c) ?c]	  'proof-ctxt)
;; NB: next binding overwrites comint-find-source-code.  Anyone miss it?
(define-key map [(control c) (control f)] 'proof-find-theorems)
(define-key map [(control c) ?f]	  'proof-help)
;; FIXME: not implemented yet 
;; (define-key map [(meta p)]		  'proof-previous-matching-command)
;; (define-key map [(meta n)]		  'proof-next-matching-command)
(proof-define-keys map proof-universal-keys))



;; the following callback is an irritating hack - there should be some
;; elegant mechanism for computing constants after the child has
;; configured.

(defun proof-config-done () 
  "Finish setup of Proof General scripting mode.
Call this function in the derived mode for the proof assistant to
finish setup which depends on specific proof assistant configuration."
  ;; Has buffer already been processed?
  ;; NB: call to file-truename is needed for FSF Emacs which
  ;; chooses to make buffer-file-truename abbreviate-file-name
  ;; form of file-truename.
  (and buffer-file-truename
       (member (file-truename buffer-file-truename)
	       proof-included-files-list)
       (proof-complete-buffer-atomic (current-buffer)))

  ;; calculate some strings and regexps for searching
  (setq proof-terminal-string (char-to-string proof-terminal-char))

  ;; FIXME da: I'm not sure we ought to add spaces here, but if
  ;; we don't, there would be trouble overloading these settings
  ;; to also use as regexps for finding comments.
  ;; 
  (make-local-variable 'comment-start)
  (setq comment-start (concat proof-comment-start " "))
  (make-local-variable 'comment-end)
  (setq comment-end (concat " " proof-comment-end))
  (make-local-variable 'comment-start-skip)
  (setq comment-start-skip 
    (concat (regexp-quote proof-comment-start) "+\\s_?"))

  ;; Additional key definitions which depend on configuration for
  ;; specific proof assistant.
  (define-key proof-mode-map
    (vconcat [(control c)] (vector proof-terminal-char))
    'proof-active-terminator-minor-mode)

  (define-key proof-mode-map (vector proof-terminal-char)
    'proof-active-terminator)

  (make-local-variable 'indent-line-function)
  (if proof-script-indent
      (setq indent-line-function 'proof-indent-line))

  ;; Toolbar and scripting menu
  ;; NB: autloads proof-toolbar, which defines proof-toolbar-scripting-menu.
  (proof-toolbar-setup)

  ;; Menu
  (easy-menu-define proof-mode-menu  
		    proof-mode-map
		    "Proof General menu"
		    (cons proof-general-name
			  (append
			   proof-toolbar-scripting-menu
			   proof-menu
			   ;; begin UGLY COMPATIBILTY HACK
			   ;; older/non-existent customize doesn't have 
			   ;; this function.  
			   (if (fboundp 'customize-menu-create)
			       (list (customize-menu-create 'proof-general)
				     (customize-menu-create
				      'proof-general-internals
				      "Internals"))
			     nil)
			   ;; end UGLY COMPATIBILTY HACK
			   proof-bug-report-menu
			   )))

  ;; Put the ProofGeneral menu on the menubar
  (easy-menu-add proof-mode-menu proof-mode-map)

  ;; For fontlock

  ;; setting font-lock-defaults explicitly is required by FSF Emacs
  ;; 20.2's version of font-lock
  (make-local-variable 'font-lock-defaults)
  (setq font-lock-defaults '(font-lock-keywords))

  ;; FIXME (da): zap commas support is too specific, should be enabled
  ;; by each proof assistant as it likes.
  (remove-hook 'font-lock-after-fontify-buffer-hook 'proof-zap-commas-buffer t)
  (add-hook 'font-lock-after-fontify-buffer-hook 
	    'proof-zap-commas-buffer nil t)
  (remove-hook 'font-lock-mode-hook 'proof-unfontify-separator t)
  (add-hook 'font-lock-mode-hook 'proof-unfontify-separator nil t)

  ;; if we don't have the following, zap-commas fails to work.
  ;; FIXME (da): setting this to t everywhere is too brutal.  Should
  ;; probably make it local.
  (and (boundp 'font-lock-always-fontify-immediately)
       (setq font-lock-always-fontify-immediately t))

  ;; Assume font-lock case folding follows proof-case-fold-search
  (setq font-lock-keywords-case-fold-search proof-case-fold-search)

  ;; Make sure func menu is configured.  (NB: Ideal place for this and
  ;; similar stuff would be in something evaluated at top level after
  ;; defining the derived mode: normally we wouldn't repeat this
  ;; each time the mode function is run, so we wouldn't need "pushnew").

  (cond ((featurep 'func-menu)
	 (unless proof-script-next-entity-regexps ; unless already set
	   ;; Try to calculate a useful default value.
	   ;; FIXME: this is rather complicated!  The use of the regexp
	   ;; variables needs sorting out. 
	     (customize-set-variable
	      'proof-script-next-entity-regexps
	      (let ((goal-discrim
		     ;; Goal discriminator searches forward for matching
		     ;; save if the regexp is set.
		     (if proof-goal-with-hole-regexp
			 (if proof-save-command-regexp
			     (list
			      proof-goal-with-hole-regexp 2
			      'forward proof-save-command-regexp)
			   (list proof-goal-with-hole-regexp 2))))
		    ;; Save discriminator searches backward for matching
		    ;; goal if the regexp is set.
		    (save-discrim
		     (if proof-save-with-hole-regexp
			 (if proof-goal-command-regexp
			     (list
			      proof-save-with-hole-regexp 2
			      'backward proof-goal-command-regexp)
			   (list proof-save-with-hole-regexp 2)))))
		(cond
		 ((and proof-goal-with-hole-regexp proof-save-with-hole-regexp)
		  (list
		   (proof-regexp-alt
		    proof-goal-with-hole-regexp
		    proof-save-with-hole-regexp) goal-discrim save-discrim))
		  
		 (proof-goal-with-hole-regexp
		  (list proof-goal-with-hole-regexp goal-discrim))
		 
		 (proof-save-with-hole-regexp
		  (list proof-save-with-hole-regexp save-discrim))))))

	   (if proof-script-next-entity-regexps
	       ;; Enable func-menu for this mode if regexps set
	       (progn
		 (pushnew
		  (cons major-mode 'proof-script-next-entity-regexps)
		  fume-function-name-regexp-alist)
		 (pushnew
		  (cons major-mode proof-script-find-next-entity-fn)
		  fume-find-function-name-method-alist)))))

  ;; Offer to save script mode buffers which have no files,
  ;; in case Emacs is exited accidently.
  (or (buffer-file-name)
      (setq buffer-offer-save t)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; FIXME FIXME FIXME da:
;;
;; want to remove this function
;; but at the moment it's used by
;; plastic instantiation.  Try
;; to persuade P.C. that we can
;; live without it?


;;         proof-try-command                                        ;;
;;         this isn't really in the spirit of script management,    ;;
;;         but sometimes the user wants to just try an expression   ;;
;;         without having to undo it in order to try something      ;;
;;         different. Of course you can easily lose sync by doing   ;;
;;         something here which changes the proof state             ;;

(defun proof-done-trying (span)
  "Callback for proof-try-command."
  (delete-span span)
  (proof-detach-queue))
			
(defun proof-try-command (&optional unclosed-comment-fun) 
  "Process the command at point, but don't add it to the locked region. 

Supplied to let the user to test the types and values of
expressions. Checks via the function proof-state-preserving-p that the
command won't change the proof state, but this isn't guaranteed to be
foolproof and may cause Proof General to lose sync with the prover.

Default action if inside a comment is just to go until the start of
the comment. If you want something different, put it inside
UNCLOSED-COMMENT-FUN."
  (interactive)
  (proof-activate-scripting)
  (let ((pt (point)) semis test)
    (save-excursion
      (if (proof-only-whitespace-to-locked-region-p)
	  (progn (goto-char pt)
		 (error "I don't know what I should be doing in this buffer!")))
      (setq semis (proof-segment-up-to (point))))
    (if (and unclosed-comment-fun (eq 'unclosed-comment (car semis)))
	(funcall unclosed-comment-fun)
      (if (eq 'unclosed-comment (car semis)) (setq semis (cdr semis)))
      (if (null semis) 
	  (error "I don't know what I should be doing in this buffer!"))
      (setq test (car semis))
      (goto-char (nth 2 test))
      (let ((vanillas (proof-semis-to-vanillas (list test)
					       'proof-done-trying)))
	(proof-start-queue (proof-unprocessed-begin) (point) vanillas)))))



(provide 'proof-script)
;; proof-script.el ends here.

;; 
;;; Lo%al Va%iables:
;;; eval: (put 'proof-if-setting-configured 'lisp-indent-function 1)
;;; eval: (put 'proof-define-assistant-command 'lisp-indent-function 'defun)
;;; eval: (put 'proof-define-assistant-command-wtharg 'lisp-indent-function 'defun)
;;; End:

