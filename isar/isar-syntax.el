;; isar-syntax.el Syntax expressions for Isabelle/Isar
;; Copyright (C) 1994-1998 LFCS Edinburgh. 
;;
;; Author:      David Aspinall <da@dcs.ed.ac.uk>
;; Maintainer:  Markus Wenzel <wenzelm@in.tum.de>
;;
;; $Id isar-syntax.el,v 2.14 1998/11/03 14:41:54 da Exp$
;;

(require 'proof-syntax)
(require 'isar-keywords)

;;; Proof mode customization: how should it work?
;;;   Presently we have a bunch of variables in proof.el which are
;;;   set from a bunch of similarly named variables in <engine>-syntax.el.
;;;
;;;   Seems a bit daft: why not just have the customization in
;;;   one place, and settings hardwired in <engine>-syntax.el.
;;;
;;;   That way we can see which settings are part of instantiation of
;;;   proof.el, and which are part of cusomization for <engine>.

;; ------ customize groups

;(defgroup isar-scripting nil
;  "Customization of Isabelle/Isar script management"
;  :group 'external
;  :group 'languages)

;(defgroup isar-syntax nil
;  "Customization of Isabelle/Isar's syntax recognition"
;  :group 'isar-scripting)

;; ----- syntax for font-lock and other features

(defgroup isar-syntax nil
  "Customization of Isabelle/Isar syntax for proof mode"
  :group 'isar-settings)


(defconst isar-keywords-theory-enclose
  (append isar-keywords-theory-begin
	  isar-keywords-theory-end))

(defconst isar-keywords-theory
  (append isar-keywords-theory-heading
	  isar-keywords-theory-decl
	  isar-keywords-theory-goal))

(defconst isar-keywords-proof-enclose
  (append isar-keywords-proof-block
	  isar-keywords-qed))

(defconst isar-keywords-proof
  (append isar-keywords-proof-goal
	  isar-keywords-proof-chain
	  isar-keywords-proof-decl))

(defconst isar-keywords
  (append isar-keywords-control isar-keywords-diag
	  isar-keywords-theory-begin isar-keywords-theory-end
	  isar-keywords-theory-heading isar-keywords-theory-decl
	  isar-keywords-theory-goal isar-keywords-qed isar-keywords-proof-goal
	  isar-keywords-proof-block isar-keywords-proof-chain
	  isar-keywords-proof-decl isar-keywords-proof-script))


;; ----- regular expressions

(defconst isar-id "\\([A-Za-z][A-Za-z0-9'_]*\\)")
(defconst isar-idx (concat isar-id "\\(\\.[0-9]+\\)?"))

(defconst isar-ids (proof-ids isar-id "[ \t]*")
  "Matches a sequence of identifiers separated by whitespace.")

(defconst isar-string "\"\\(\\([^\\\"]\\|\\\\\"\\)*\\)\"")

(defconst isar-name-regexp
  (concat "\\s-*\\(?:" isar-string "\\|" isar-id "\\)\\s-*")
  "Regexp matching Isabelle/Isar names, with contents bracketed.")

(defvar isar-font-lock-terms
  (list
   (cons (concat "\351" isar-id "\350") 'proof-declaration-name-face)    ; class
   (cons (concat "\352'" isar-id "\350") 'proof-tacticals-name-face)     ; tfree
   (cons (concat "\353\\?'" isar-idx "\350") 'font-lock-type-face)       ; tvar
   (cons (concat "\354" isar-id "\350") 'font-lock-function-face)        ; free
   (cons (concat "\355" isar-id "\350") 'font-lock-keyword-face)         ; bound
   (cons (concat "\356" isar-idx "\350") 'font-lock-function-face)       ; var
   )
  "*Font-lock table for Isabelle terms.")

(defconst isar-save-command-regexp
  (concat "^" (proof-ids-to-regexp isar-keywords-qed)))

(defconst isar-save-with-hole-regexp "$^") ; n.a.

(defcustom isar-goal-command-regexp
  (proof-ids-to-regexp isar-keywords-theory-goal)
  "Regular expression used to match a global goal."
  :type 'regexp
  :group 'isabelle-isar-config)

(defcustom isar-local-goal-command-regexp
  (proof-ids-to-regexp isar-keywords-proof-goal)
  "Regular expression used to match a local goal."
  :type 'regexp
  :group 'isabelle-isar-config)

(defconst isar-goal-with-hole-regexp
  (concat "\\(" (proof-ids-to-regexp isar-keywords-theory-goal) "\\)" isar-name-regexp ":")
  "Regexp matching goal commands in Isabelle/Isar which name a theorem")


(defvar isar-font-lock-keywords-1
  (append
   isar-font-lock-terms
   (list
    (cons (proof-ids-to-regexp isar-keywords-minor) 'font-lock-type-face)
    (cons (proof-ids-to-regexp isar-keywords-control) 'proof-error-face)
    (cons (proof-ids-to-regexp isar-keywords-diag) 'proof-tacticals-name-face)
    (cons (proof-ids-to-regexp isar-keywords-theory-enclose) 'font-lock-function-name-face)
    (cons (proof-ids-to-regexp isar-keywords-theory) 'font-lock-keyword-face)
    (cons (proof-ids-to-regexp isar-keywords-proof-enclose) 'font-lock-function-name-face)
    (cons (proof-ids-to-regexp isar-keywords-proof) 'font-lock-keyword-face)
    (cons (proof-ids-to-regexp isar-keywords-proof-script) 'font-lock-reference-face))))

(provide 'isar-syntax)
