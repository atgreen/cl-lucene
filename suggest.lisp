;;;; suggest.lisp --- Autocomplete suggestions.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT
;;;;
;;;; An in-memory infix autocomplete suggester (Lucene's AnalyzingInfixSuggester):
;;;; add weighted strings, commit, then look up completions of a prefix or any
;;;; infix.  Separate from the main index.

(in-package #:cl-lucene)

(defstruct (suggester (:constructor %make-suggester))
  "An AnalyzingInfixSuggester and the in-memory directory backing it."
  object
  directory)

(defun make-suggester (&key (analyzer :standard))
  "Create an in-memory autocomplete suggester.  ANALYZER (see MAKE-ANALYZER)
tokenizes both the added text and the lookup key.  Close it with CLOSE."
  (start)
  (let ((directory (java-new "org.apache.lucene.store.ByteBuffersDirectory" "()")))
    (%make-suggester
     :object (java-new "org.apache.lucene.search.suggest.analyzing.AnalyzingInfixSuggester"
                       "(Lorg/apache/lucene/store/Directory;Lorg/apache/lucene/analysis/Analyzer;)"
                       directory (make-analyzer analyzer))
     :directory directory)))

(defun suggest-add (suggester text &key (weight 1))
  "Add TEXT, ranked by WEIGHT (higher sorts first), to SUGGESTER.  Call
SUGGEST-COMMIT before SUGGEST sees newly added entries."
  (with-foreign-errors ("Lucene")
    (java-call "add(Lorg/apache/lucene/util/BytesRef;Ljava/util/Set;JLorg/apache/lucene/util/BytesRef;)V"
               (suggester-object suggester)
               (java-new "org.apache.lucene.util.BytesRef" "(Ljava/lang/CharSequence;)" (jstring text))
               nil (round weight) nil))
  suggester)

(defun suggest-commit (suggester)
  "Make SUGGESTER's added entries available to SUGGEST."
  (with-foreign-errors ("Lucene")
    (java-call "refresh()V" (suggester-object suggester)))
  suggester)

(defun suggest (suggester text &key (limit 10))
  "Up to LIMIT completions of TEXT from SUGGESTER, as a list of (text . weight),
best first.  TEXT matches at the start of any token (infix)."
  (with-foreign-errors ("Lucene")
    (let ((results (java-call "lookup(Ljava/lang/CharSequence;IZZ)Ljava/util/List;"
                              (suggester-object suggester) (jstring text) limit 1 0)))
      (loop for i below (java-call "size()I" results)
            for result = (java-call "get(I)Ljava/lang/Object;" results i)
            collect (cons (lstring (java-call "toString()Ljava/lang/String;"
                                              (java-field-value result "key")))
                          (java-field-value result "value"))))))

(defmethod close ((suggester suggester))
  (java-call "close()V" (suggester-object suggester))
  (java-call "close()V" (suggester-directory suggester))
  (values))
