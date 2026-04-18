;; (eval-when (:compile-toplevel :load-toplevel :execute)
;;   (unless (find-package :fiveam)
;;     ;; prefer fiveam-asdf (ASDF integration) then fall back to fiveam
;;     (or (ignore-errors (asdf:load-system :fiveam-asdf))
;;         (ignore-errors (asdf:load-system :fiveam)))))

;(eval-when (:compile-toplevel :load-toplevel :execute)
;  (unless (find-package :parachute)
;    (ignore-errors (asdf:load-system :parachute))))

(asdf:defsystem #:easytags
  :description "Tags files are directories"
  :author "John Doe"
  :license  "GPL-3.0-or-later"
  :version "0.0.1"
  :serial t
  :depends-on (:clingon :cl-ppcre)
  :components ((:file "package")
               (:file "utils")
               (:file "easytags"))
  :build-operation "program-op"
  :build-pathname "easytags"
  :entry-point "easytags::main"
  :in-order-to ((test-op (test-op "easytags/test"))))

(asdf:defsystem #:easytags/test
  :depends-on (:easytags :fiveam)
  :components ((:file "easytags-test"))
;  :perform (test-op (o c) (symbol-call :fiveam :run! :suite1))
)
