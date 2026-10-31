;;;; join.lisp --- Nested documents and block join.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT
;;;;
;;;; Index a parent document together with its children as one block
;;;; (ADD-BLOCK), then find parents by their children with BLOCK-JOIN-QUERY
;;;; (Lucene's ToParentBlockJoinQuery).  Mark parents with a field so a query
;;;; can identify them.

(in-package #:cl-lucene)

(defun add-block (writer parent children)
  "Index PARENT and its CHILDREN as one nested block.  PARENT and each of
CHILDREN are field-spec lists as ADD-DOCUMENT takes.  Children are written
first and the parent last, as Lucene's block join requires.  Give the parent a
marker field, e.g. (\"kind\" \"parent\" :type :string), so BLOCK-JOIN-QUERY can
identify parents."
  (with-foreign-errors ("Lucene")
    (let ((block (java-new "java.util.ArrayList" "()")))
      (dolist (child children)
        (java-call "add(Ljava/lang/Object;)Z" block (build-document child)))
      (java-call "add(Ljava/lang/Object;)Z" block (build-document parent))
      (java-call "addDocuments(Ljava/lang/Iterable;)J" (writer-object writer) block)))
  writer)

(defparameter *join-score-modes*
  '((:none . "None") (:avg . "Avg") (:max . "Max") (:min . "Min") (:total . "Total"))
  "Keyword names for the join ScoreMode (how child scores roll up to a parent).")

(defun block-join-query (child-query parent-query &key (score :avg))
  "A query matching PARENT documents that have at least one child matching
CHILD-QUERY.  PARENT-QUERY must match exactly the parent documents (e.g. a
TERM-QUERY on the parents' marker field).  SCORE rolls child scores up to the
parent: :avg (default), :max, :min, :total, or :none."
  (start)
  (java-new "org.apache.lucene.search.join.ToParentBlockJoinQuery"
            (concatenate 'string "(Lorg/apache/lucene/search/Query;"
                         "Lorg/apache/lucene/search/join/BitSetProducer;"
                         "Lorg/apache/lucene/search/join/ScoreMode;)")
            child-query
            (java-new "org.apache.lucene.search.join.QueryBitSetProducer"
                      "(Lorg/apache/lucene/search/Query;)" parent-query)
            (java-static-field "org.apache.lucene.search.join.ScoreMode"
                               (or (cdr (assoc score *join-score-modes*))
                                   (error "Unknown score mode ~S" score)))))
