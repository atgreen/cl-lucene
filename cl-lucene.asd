;;;; cl-lucene.asd --- A native Common Lisp API for Apache Lucene on OpenLDK.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(asdf:defsystem "cl-lucene"
  :description "A native Common Lisp API for Apache Lucene, running on OpenLDK."
  :author "Anthony Green <green@moxielogic.com>"
  :license "MIT"
  :version "1.0.0"
  :depends-on ("openldk/interop")
  :serial t
  :components ((:file "package")
               (:file "runtime")
               (:file "document")
               (:file "analysis")
               (:file "query")
               (:file "parser")
               (:file "index")
               (:file "search")
               (:file "facet")
               (:file "suggest")
               (:file "group")
               (:file "join"))
  :in-order-to ((test-op (test-op "cl-lucene/tests"))))

(asdf:defsystem "cl-lucene/tests"
  :description "Tests for cl-lucene."
  :depends-on ("cl-lucene" "fiveam")
  :serial t
  :components ((:module "tests"
                :components ((:file "tests"))))
  :perform (test-op (op c)
             (unless (uiop:symbol-call :fiveam :run! (uiop:find-symbol* :cl-lucene :cl-lucene/tests))
               (error "cl-lucene tests failed"))))
