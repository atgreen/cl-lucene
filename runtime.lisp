;;;; runtime.lisp --- Bootstrapping the OpenLDK runtime with Lucene on the classpath.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(in-package #:cl-lucene)

(defparameter *lucene-version* "10.6.0"
  "The version of Apache Lucene to put on the classpath.")

(defparameter *lucene-artifacts*
  '("lucene-core" "lucene-analysis-common" "lucene-queryparser"
    "lucene-queries" "lucene-memory" "lucene-facet" "lucene-highlighter"
    "lucene-suggest" "lucene-grouping" "lucene-join")
  "The org.apache.lucene Maven artifacts cl-lucene needs on the classpath.
lucene-queries and lucene-memory supply the span and MemoryIndex classes the
UnifiedHighlighter links against.")

(defvar *started* nil
  "True once START has brought up the runtime with Lucene on the classpath.")

(defun lucene-jars ()
  "The Lucene jars for *LUCENE-VERSION*, downloading any that OpenLDK has not
yet cached, and returning their pathnames."
  (mapcar (lambda (artifact)
            (maven-jar (format nil "org.apache.lucene:~A:~A" artifact *lucene-version*)))
          *lucene-artifacts*))

(defun start (&key extra-jars)
  "Start the OpenLDK Java runtime with the Lucene jars, and EXTRA-JARS (a list
of jar pathnames or namestrings), on the classpath.  Idempotent: calling it
again only adds EXTRA-JARS to the classpath."
  (if *started*
      (when extra-jars (start-runtime :classpath extra-jars))
      (progn
        (start-runtime :classpath (append (lucene-jars) extra-jars))
        (setf *started* t)))
  t)

;;; Field.Store is an enum; its two constants are fetched once the runtime is up.

(defvar *store-yes* nil)
(defvar *store-no* nil)

(defun field-store (store)
  "The org.apache.lucene.document.Field.Store constant for STORE: YES for T or
:YES, NO for NIL or :NO."
  (ecase store
    ((t :yes)
     (or *store-yes*
         (setf *store-yes* (java-static-field "org.apache.lucene.document.Field$Store" "YES"))))
    ((nil :no)
     (or *store-no*
         (setf *store-no* (java-static-field "org.apache.lucene.document.Field$Store" "NO"))))))

(defun java-path (path)
  "A java.nio.file.Path for PATH (a pathname or namestring)."
  (java-static "java.nio.file.Paths"
               "get(Ljava/lang/String;[Ljava/lang/String;)Ljava/nio/file/Path;"
               (jstring (uiop:native-namestring path))
               (make-java-array-of "java.lang.String" '())))

(defun java-field-value (object name)
  "The value of the Java instance field NAME (a string) of OBJECT."
  (cdr (assoc name (java-fields object) :test #'string=)))

(defun float-array (sequence)
  "A Java float[] built from the Lisp SEQUENCE of real numbers."
  (make-java-array-of "float" (map 'list (lambda (x) (coerce x 'single-float)) sequence)))

(defun string-array (strings)
  "A Java String[] from the Lisp list STRINGS (each a string designator)."
  (make-java-array-of "java.lang.String"
                      (mapcar (lambda (s) (jstring (string s))) strings)))

(defun java-float (number)
  "NUMBER as a boxed java.lang.Float."
  (java-static "java.lang.Float" "valueOf(F)Ljava/lang/Float;" (coerce number 'single-float)))

;;; CLOSE is a generic function over cl-lucene's wrapper objects (writers,
;;; searchers, directories), each defined with its own method.

(defgeneric close (object)
  (:documentation "Release the Lucene resource OBJECT: a writer, a searcher, or
a directory.  Closing a writer or searcher that owns its directory closes the
directory too."))
