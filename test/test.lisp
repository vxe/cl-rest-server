(defpackage :rest-server-tests
  (:use :cl :rest-server :fiveam)
  (:export :run-tests :debug-tests))

(in-package :rest-server-tests)

(def-suite rest-server-tests :description "rest-server system tests")

(defun run-tests ()
  (run 'rest-server-tests))

(defun debug-tests ()
  (debug! 'rest-server-tests))

(in-suite rest-server-tests)